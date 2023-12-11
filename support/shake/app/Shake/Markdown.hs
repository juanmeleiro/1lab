{-# LANGUAGE BlockArguments, OverloadedStrings, FlexibleContexts, ViewPatterns, LambdaCase #-}

{-| Convert a markdown file to templated HTML, applying several
post-processing steps and rendered to HTML using the
@support/web/template.html@ template.
-}
module Shake.Markdown (buildMarkdown, readLabMarkdown) where

import Control.Monad.Error.Class
import Control.Monad.IO.Class
import Control.Monad.Writer
import Control.Monad.State
import Control.Applicative

import qualified Data.ByteString.Lazy as LazyBS
import qualified Data.Text.Encoding as Text
import qualified Data.Map.Lazy as Map
import qualified Data.Text.IO as Text
import qualified Data.Text as Text
import qualified Data.Set as Set

import Data.Digest.Pure.SHA
import Data.Foldable
import Data.Aeson (encodeFile)
import Data.Maybe
import Data.Text (Text)

import qualified System.Directory as Dir

import Development.Shake.FilePath
import Development.Shake

import qualified Citeproc as Cite
import Text.DocTemplates
import Text.HTML.TagSoup
import Text.HTML.TagSoup.Match
import Text.HTML.TagSoup.Tree

import Text.Pandoc.Builder (Inlines)
import Text.Pandoc.Citeproc
import Text.Pandoc.Shared
import Text.Collate.Lang (Lang (..))
import Text.Pandoc.Walk
import Text.Pandoc

import Shake.LinkReferences
import Shake.SearchData
import Shake.Highlights
import Shake.Options
import Shake.KaTeX
import Shake.Git

import HTML.Emit

import Definitions

readLabMarkdown :: MonadIO m => FilePath -> m Pandoc
readLabMarkdown fp = liftIO cont where
  ourExts :: [Extension]
  ourExts = [ Ext_wikilinks_title_before_pipe ]

  badExts :: [Extension]
  badExts = [Ext_definition_lists, Ext_compact_definition_lists]

  theExts :: Extensions
  theExts =
    foldr disableExtension
      (foldr enableExtension (getDefaultExtensions "markdown") ourExts)
      badExts

  cont :: IO Pandoc
  cont = do
    contents <- mangleMarkdown <$> Text.readFile fp
    either (fail . show) pure =<< runIO do
      doc <- readMarkdown def { readerExtensions = theExts } [(fp, contents)]
      pure $ walk postParseInlines doc

-- | Patch a sequence of inline elements. `patchInline' should be preferred
-- where possible, this is only useful when you cannot modify inlines in
-- isolation.
postParseInlines :: [Inline] -> [Inline]

-- Replace any expression $foo$-bar with <span ...>$foo$-bar</span>, so that
-- the equation is not split when word wrapping.
postParseInlines (m@Math{}:s@(Str txt):xs)
  | not (Text.isPrefixOf " " txt)
  = htmlInl "<span style=\"white-space: nowrap;\">" : m : s : htmlInl "</span>"
  : postParseInlines xs

-- Parse the contents of wikilinks as markdown. While Pandoc doesn't
-- read the title part of a wikilink, it will always consist of a single
-- Str span. We call the Pandoc parser in a pure context to read the
-- title part as an actual list of inlines.
postParseInlines (Link attr [Str contents] (url, "wikilink"):xs) =
  link' `seq` link':postParseInlines xs where

  try  = either (const Nothing) Just . runPure
  fail = error $
    "Failed to parse contents of wikilink as Markdown:" <> Text.unpack contents

  link' = fromMaybe fail do
    -- The contents of a link are valid if they consist of a single list
    -- of inlines. Pandoc doesn't let us parse a list of inlines, but we
    -- can still parse it as a document and ensure that (a) everything
    -- got bunched in the same paragraph and (b) there was no metadata.
    parsed@(Pandoc (Meta m) [Para is]) <- try (readMarkdown def contents)
    guard (null m) -- I don't foresee this ever failing.

    -- Rendering the contents as plain text will strip all the
    -- decorations, thus recovering the "underlying page" that was meant
    -- to be linked to. Of course, we should only try changing the
    -- target if the link looks like [[foo]], rather than [[foo|bar]].
    let
      target = if url == contents
        then stringify parsed
        else url

    -- Note that Pandoc doesn't distinguish between [[foo]] and
    -- [[foo|foo]], so really the only way is checking whether the URL
    -- is equal to the contents string. If that was the case, then
    -- stripping formatting is the right thing, otherwise e.g. [[*path
    -- induction*]] would fail since the target "*path-induction*"
    -- doesn't exist.
    pure (Link attr is (target, "wikilink"))

postParseInlines (x:xs) = x:postParseInlines xs
postParseInlines [] = []

-- | Pandoc's wiki-link extension does not support splitting the guts of
-- a wikilink over multiple lines. The function 'mangleMarkdown'
-- pre-processes the input file so that any invalid space characters
-- inside a wikilink are replaced by the safe ASCII space @ @.
mangleMarkdown :: Text -> Text
mangleMarkdown = Text.pack . toplevel . Text.unpack where
  toplevel ('[':'[':cs) = '[':'[':wikilink cs
  toplevel (c:cs)       = c:toplevel cs
  toplevel []           = []

  wikilink (']':']':cs) = ']':']':toplevel cs

  wikilink ('\n':cs)    = ' ':wikilink cs
  wikilink ('\t':cs)    = ' ':wikilink cs
  wikilink ('\f':cs)    = ' ':wikilink cs
  wikilink ('\r':cs)    = ' ':wikilink cs

  wikilink (c:cs)       = c:wikilink cs
  wikilink []           = []

buildMarkdown :: String   -- ^ The name of the Agda module.
              -> FilePath -- ^ Input markdown file, produced by the Agda compiler.
              -> FilePath -- ^ Output HTML file.
              -> Action ()
buildMarkdown modname input output = do
  gitCommit <- gitCommit
  skipAgda <- getSkipAgda

  need [templateName, bibliographyName, input]

  modulePath <- findModule modname
  authors <- gitAuthors modulePath
  let
    permalink = gitCommit </> modulePath

    title
      | length modname > 24 = '…':reverse (take 24 (reverse modname))
      | otherwise = modname

    mStr = MetaString . Text.pack
    patchMeta
      = Meta
      . Map.insert "title" (mStr title)
      . Map.insert "source" (mStr permalink)
      . Map.insert "bibliography" (mStr bibliographyName)
      . Map.insert "link-citations" (MetaBool True)
      . unMeta

  (markdown, references) <- traced "pandoc" do
    Pandoc meta markdown <- readLabMarkdown input
    let pandoc = addPageTitle (Pandoc (patchMeta meta) markdown)
    either (fail . show) pure =<< runIO do
      (,) <$> processCitations pandoc <*> getReferences Nothing pandoc

  liftIO $ Dir.createDirectoryIfMissing False "_build/diagrams"

  let refMap = Map.fromList $ map (\x -> (Cite.unItemId . Cite.referenceId $ x, x)) references

  markdown <-
      walkM (patchInline refMap)
    . (if skipAgda then id else linkReferences modname)
    . walk uncommentAgda
    $ markdown

  -- Rendering the search data has to be done *here*, after running the
  -- maths through KaTeX but before adding the emoji to headers.
  let search = query (getHeaders (Text.pack modname)) markdown

  (markdown, MarkdownState references dependencies) <- runWriterT (walkM patchBlock markdown)
  need dependencies

  baseUrl <- getBaseUrl
  text <- liftIO $ either (fail . show) pure =<<
    runIO (renderMarkdown authors references modname baseUrl markdown)

  let tags = foldEquations False (parseTags text)
  tags <- renderHighlights tags
  traverse_ (checkMarkup input) tags

  traced "writing" do
    Text.writeFile output $ renderHTML5 tags
    Dir.createDirectoryIfMissing False "_build/search"
    encodeFile ("_build/search" </> modname <.> "json") search

-- | Find the original Agda file from a 1Lab module name.
findModule :: MonadIO m => String -> m FilePath
findModule modname = do
  let toPath '.' = '/'
      toPath c = c
  let modfile = "src" </> map toPath modname

  exists <- liftIO $ Dir.doesFileExist (modfile <.> "lagda.md")
  pure $ if exists
    then modfile <.> "lagda.md"
    else modfile <.> "agda"

-- | Adds the first level-1 header as a page title, if one has not
-- already been provided by the author.
addPageTitle :: Pandoc -> Pandoc
addPageTitle (Pandoc (Meta meta) m) = Pandoc (Meta meta') m where
  search (Header 1 _ inl:_) = Just (MetaInlines inl)
  search (_:xs)             = search xs
  search []                 = Nothing

  meta' = case Map.lookup "pagetitle" meta <|> Map.lookup "customtitle" meta <|> search m of
    Just m  -> Map.insert "pagetitle" m meta
    Nothing -> meta

-- | Rescue Agda code blocks from under HTML comments so we can show them if needed.
uncommentAgda :: Block -> Block
uncommentAgda (RawBlock "html" (parseTags -> [TagComment html])) | any isAgdaBlock (parseTree html) =
  Div ("", ["commented-out"], []) [RawBlock "html" html]
uncommentAgda b = b

isAgdaBlock :: TagTree Text -> Bool
isAgdaBlock (TagBranch _ attrs _) = anyAttrLit ("class", "Agda") attrs
isAgdaBlock _ = False

-- | Rewrite a single inline element.
patchInline
  :: Map.Map Text (Cite.Reference Inlines)
  -- ^ A lookup of reference names to the actual reference.
  -> Inline
  -> Action Inline
-- Pre-render latex equations.
patchInline _ (Math DisplayMath contents) = htmlInl <$> getDisplayMath contents
patchInline _ (Math InlineMath contents) = htmlInl <$> getInlineMath contents

patchInline _ l@Link{} | Just wikil <- isWikiLink l = getWikiLink wikil

-- Add the title to reference links.
patchInline refMap (Link attrs contents (target, ""))
  | Just citation <- Text.stripPrefix "#ref-" target
  , Just ref      <- Map.lookup citation refMap
  , Just title    <- Cite.valToText =<< Cite.lookupVariable "title" ref
  = pure $ Link attrs contents (target, title)

patchInline _ (Str s)
  | "[" `Text.isPrefixOf` s
  , s /= "[", s /= "[…]" -- "[" appears on its own before citations
  = error ("possible broken link: " <> Text.unpack s)

patchInline _ h = pure h


data MarkdownState = MarkdownState
  { mdReferences :: [Val Text] -- ^ List of references extracted from Pandoc's "reference" div.
  , mdDependencies :: [String] -- ^ Additional files this markdown file depends on.
  }

instance Semigroup MarkdownState where
  (MarkdownState r s) <> (MarkdownState r' s') = MarkdownState (r <> r') (s <> s')

instance Monoid MarkdownState where
  mempty = MarkdownState mempty mempty


-- | Patch a Pandoc block element.
patchBlock
  :: (MonadIO f, MonadFail f, MonadWriter MarkdownState f)
  => Block
  -> f Block
-- Make all headers links, and add an anchor emoji.
patchBlock (Header i a@(ident, _, _) inl) = pure $ Header i a
  $ htmlInl (Text.concat ["<a href=\"#", ident, "\" class=\"header-link\"><span>"])
  : inl
  ++ [htmlInl "</span><span class=\"header-link-emoji\">🔗</span></a>"]

-- Replace quiver code blocks with a link to an SVG file, and depend on the SVG file.
patchBlock (CodeBlock (id, classes, attrs) contents) | "quiver" `elem` classes = do
  let
    digest = showDigest . sha1 . LazyBS.fromStrict $ Text.encodeUtf8 contents
    title = fromMaybe "commutative diagram" (lookup "title" attrs)
  liftIO $ Text.writeFile ("_build/diagrams" </> digest <.> "tex") contents
  tell mempty {
    mdDependencies =
      [ "_build/html/light-" <> digest <.> "svg"
      , "_build/html/dark-" <> digest <.> "svg"
      ]
    }

  pure $ Div ("", ["diagram-container"], [])
    [ Plain [ Image (id, "diagram diagram-light":classes, attrs) [] (Text.pack ("light-" <> digest <.> "svg"), title) ]
    , Plain [ Image (id, "diagram diagram-dark":classes, attrs) [] (Text.pack ("dark-" <> digest <.> "svg"), title) ]
    ]

-- Find the references block, parse the references, and remove it. We write
-- the references as part of our template instead.
patchBlock (Div ("refs", _, _) body) = do
  for_ body \ref -> case ref of
    (Div (id, _, _) body) -> do
      -- If our citation is a single paragraph, don't wrap it in <p>.
      let body' = case body of
            [Para p] -> [Plain p]
            body -> body
      -- Now render it the citation itself to HTML and add it to our template
      -- context.
      body <- either (fail . show) pure . runPure $
        writeHtml5String def { writerExtensions = getDefaultExtensions "html" } (Pandoc mempty body')
      let ref = Context $ Map.fromList
                [ ("id", toVal id)
                , ("body", toVal body)
                ]
      tell mempty { mdReferences = [ MapVal ref ]}

    _ -> fail ("Unknown reference node " ++ show ref)
  pure $ Plain [] -- TODO: pandoc-types 1.23 removed Null

patchBlock h = pure h


-- | Render our Pandoc document using the given template variables.
renderMarkdown :: PandocMonad m
               => [Text]       -- ^ List of authors
               -> [Val Text]   -- ^ List of references
               -> String       -- ^ Name of the current module
               -> String       -- ^ Base URL
               -> Pandoc -> m Text
renderMarkdown authors references modname baseUrl markdown = do
  template <- getTemplate templateName >>= runWithPartials . compileTemplate templateName
                >>= either (throwError . PandocTemplateError . Text.pack) pure
  let
    authors' = case authors of
      [] -> "Nobody"
      [x] -> x
      _ -> Text.intercalate ", " (init authors) `Text.append` " and " `Text.append` last authors

    context = Context $ Map.fromList $
      [ ("is-index",     toVal (modname == "index"))
      , ("authors",      toVal authors')
      , ("reference",    toVal references)
      , ("base-url",     toVal (Text.pack baseUrl))
      ]

    options = def { writerTemplate        = Just template
                  , writerTableOfContents = True
                  , writerVariables       = context
                  , writerExtensions      = getDefaultExtensions "html"
                  }
  setTranslations (Lang "en" Nothing Nothing [] [] [])
  writeHtml5String options markdown

-- | Simple textual list of starting identifiers not to fold
don'tFold :: Set.Set Text
don'tFold = Set.fromList
  [ "`⟨" -- used in CC.Lambda
  ]

-- | Removes the RHS of equation reasoning steps?? IDK, ask Amelia.
foldEquations :: Bool -> [Tag Text] -> [Tag Text]
foldEquations _ (to@(TagOpen "a" attrs):tt@(TagText t):tc@(TagClose "a"):rest)
  | t `Set.notMember` don'tFold, Text.length t > 1, Text.last t == '⟨', Just href <- lookup "href" attrs =
  [ TagOpen "span" [("class", "reasoning-step")]
  , TagOpen "span" [("class", "as-written " <> fromMaybe "" (lookup "class" attrs))]
  , to, tt, tc ] ++ go href rest
  where
    alternate = Text.init t
    go href (to@(TagOpen "a" attrs):tt@(TagText t):tc@(TagClose "a"):cs)
      | Text.length t >= 1
      , Text.head t == '⟩'
      , Just href' <- lookup "href" attrs
      , href' == href
      = [ to, tt, tc, TagClose "span"
      , TagOpen "span" [("class", "alternate " <> fromMaybe "" (lookup "class" attrs))]
      , TagText alternate
      , TagClose "span"
      , TagClose "span"
      ] ++ foldEquations True cs
    go href (c:cs) = c:go href cs
    go _ [] = []
foldEquations False (TagClose "html":cs) =
  [TagOpen "style" [], TagText ".equations { display: none !important; }", TagClose "style", TagClose "html"]
  ++ foldEquations True cs
foldEquations has_eqn (c:cs) = c:foldEquations has_eqn cs
foldEquations _ [] = []

-- | Get all headers in the document, building a list of definitions for our
-- search index.
getHeaders :: Text -> Pandoc -> [SearchTerm]
getHeaders module' markdown@(Pandoc (Meta meta) _) =
  (:) main . flip evalState [] . getAp . query (Ap . go) $ markdown
  where
  main = SearchTerm
    { idIdent = module'
    , idAnchor = module' <> ".html"
    , idType = Nothing
    , idDefines = Nothing
    }

  hasRaw :: [Inline] -> Bool
  hasRaw = any \case
    RawInline{} -> True
    _ -> False

  -- The state stores a path of headers in the document of the form (level,
  -- header), which is updated as we walk down the document.
  go :: [Block] -> State [(Int, Text)] [SearchTerm]
  go [] = pure []
  go (Header level (hId, _, keys) hText:xs) | not (hasRaw hText) = do
    path <- get
    let title = trimr (renderPlain hText)
    let path' = (level, title):dropWhile (\(l, _) -> l >= level) path
    put path'

    if hId == "" then go xs
    else
      (:) SearchTerm
        { idIdent  = Text.intercalate " > " . reverse $ map snd path'
        , idAnchor = module' <> ".html#" <> hId
        , idType   = Nothing
        , idDefines = Text.words <$> lookup "defines" keys
        } <$> go xs
  go (Div (hId, _, keys) blocks:xs) | hId /= "" = do
    path <- get

    (:) SearchTerm
      { idIdent  = Text.intercalate " > " . reverse $ hId:map snd path
      , idAnchor = module' <> ".html#" <> hId
      , idType   = Nothing
      , idDefines = (:) hId . Text.words <$> lookup "alias" keys
      } <$> go xs
  go (_:xs) = go xs

  -- writePlain won't render *markdown*, e.g. links, but it *will*
  -- preserve raw HTML - as long as we tell it to. Since any mathematics
  -- in the description will have been rendered to raw HTML by this
  -- point, that's exactly what we want!
  write = writePlain def{ writerExtensions = enableExtension Ext_raw_html (writerExtensions def) }
  renderPlain inlines = either (error . show) id . runPure . write $ Pandoc mempty [Plain inlines]

htmlInl :: Text -> Inline
htmlInl = RawInline "html"

templateName, bibliographyName :: FilePath
templateName = "support/web/template.html"
bibliographyName = "src/bibliography.bibtex"
