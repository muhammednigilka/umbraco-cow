<#
  backfill-pageblocks.ps1 -- one-shot block-list backfill for Home, About, Moo Family pages.
  Generates deterministic GUIDs per block and patches the <blocks> property in each page's
  uSync content XML with a valid Umbraco 17 BlockList value.

  Idempotent: rerunning produces the same GUIDs and overwrites the same XML.

  Element type GUIDs (from uSync/v17/ContentTypes/):
    heroBanner    e1a00001-0000-0000-0000-000000000001
    headingBlock  db096faa-0e2d-4c32-882a-1cf10ae8bb94
    richTextBlock 6b3cf24d-4934-4093-b793-31c417a271fa
    ctaBlock      a5e996c2-c7e5-4e1e-a69a-12332079a5e4
    statBlock     e1a00002-0000-0000-0000-000000000002
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
)

$ErrorActionPreference = 'Stop'
$contentRoot = Join-Path $RepoRoot 'src\MooFamily.Cms.Web\uSync\v17\Content'

function New-DGuid([string]$key) {
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = $md5.ComputeHash([Text.Encoding]::UTF8.GetBytes("moofamily-block:$key"))
    $bytes[6] = ($bytes[6] -band 0x0f) -bor 0x40
    $bytes[8] = ($bytes[8] -band 0x3f) -bor 0x80
    return [Guid]::new($bytes).ToString('D')
}

# Element type GUIDs
$ET = @{
    heroBanner       = 'e1a00001-0000-0000-0000-000000000001'
    headingBlock     = 'db096faa-0e2d-4c32-882a-1cf10ae8bb94'
    richTextBlock    = '6b3cf24d-4934-4093-b793-31c417a271fa'
    ctaBlock         = 'a5e996c2-c7e5-4e1e-a69a-12332079a5e4'
    statBlock        = 'e1a00002-0000-0000-0000-000000000002'
    featureCard      = 'e1a00003-0000-0000-0000-000000000003'
    timelineItem     = 'e1a00004-0000-0000-0000-000000000004'
    newsletterSignup = 'e1a00006-0000-0000-0000-000000000006'
}

function New-Block($page, $position, $elementAlias, $values) {
    $contentKey = New-DGuid "$page-$position-$elementAlias"
    return [pscustomobject]@{
        ContentKey      = $contentKey
        ContentTypeKey  = $ET[$elementAlias]
        Values          = $values
    }
}

function Build-BlockListJson($blocks) {
    $layout = @($blocks | ForEach-Object { @{ contentKey = $_.ContentKey } })
    $contentData = @($blocks | ForEach-Object {
        @{
            key             = $_.ContentKey
            contentTypeKey  = $_.ContentTypeKey
            values          = @($_.Values | ForEach-Object {
                @{ editorAlias = $_.editorAlias; alias = $_.alias; value = $_.value; culture = $null; segment = $null }
            })
        }
    })
    $expose = @($blocks | ForEach-Object { @{ contentKey = $_.ContentKey; culture = $null; segment = $null } })
    $obj = @{
        layout       = @{ 'Umbraco.BlockList' = $layout }
        contentData  = $contentData
        settingsData = @()
        expose       = $expose
    }
    return ($obj | ConvertTo-Json -Depth 10 -Compress)
}

# Reusable rich-text block factory
function V-RichText($html) { @{ editorAlias='Umbraco.RichText'; alias='content'; value="<p>$html</p>" } }
function V-Heading($text, $level) {
    @(
        @{ editorAlias='Umbraco.TextBox'; alias='headingText'; value=$text },
        @{ editorAlias='Umbraco.DropDown.Flexible'; alias='headingLevel'; value="[`"$level`"]" }
    )
}
function V-Hero($title, $subtitle, $body, $cta1Label, $cta1Url, $cta2Label, $cta2Url) {
    @(
        @{ editorAlias='Umbraco.TextBox'; alias='bannerTitle'; value=$title },
        @{ editorAlias='Umbraco.TextBox'; alias='bannerSubtitle'; value=$subtitle },
        @{ editorAlias='Umbraco.TextArea'; alias='bannerBody'; value=$body },
        @{ editorAlias='Umbraco.TextBox'; alias='ctaPrimaryLabel'; value=$cta1Label },
        @{ editorAlias='Umbraco.TextBox'; alias='ctaPrimaryUrl'; value=$cta1Url },
        @{ editorAlias='Umbraco.TextBox'; alias='ctaSecondaryLabel'; value=$cta2Label },
        @{ editorAlias='Umbraco.TextBox'; alias='ctaSecondaryUrl'; value=$cta2Url }
    )
}
function V-Stat($value, $label) {
    @(
        @{ editorAlias='Umbraco.TextBox'; alias='statValue'; value=$value },
        @{ editorAlias='Umbraco.TextBox'; alias='statLabel'; value=$label }
    )
}
function V-Cta($label, $url, $style) {
    @(
        @{ editorAlias='Umbraco.TextBox'; alias='label'; value=$label },
        @{ editorAlias='Umbraco.TextBox'; alias='url'; value=$url },
        @{ editorAlias='Umbraco.DropDown.Flexible'; alias='style'; value="[`"$style`"]" },
        @{ editorAlias='Umbraco.TrueFalse'; alias='openInNewTab'; value='0' }
    )
}
function V-Newsletter($title, $description, $ctaLabel, $placeholder) {
    @(
        @{ editorAlias='Umbraco.TextBox'; alias='newsletterTitle'; value=$title },
        @{ editorAlias='Umbraco.TextArea'; alias='newsletterDescription'; value=$description },
        @{ editorAlias='Umbraco.TextBox'; alias='newsletterCtaLabel'; value=$ctaLabel },
        @{ editorAlias='Umbraco.TextBox'; alias='newsletterPlaceholder'; value=$placeholder }
    )
}
function V-Feature($number, $title, $description) {
    @(
        @{ editorAlias='Umbraco.TextBox'; alias='featureNumber'; value=$number },
        @{ editorAlias='Umbraco.TextBox'; alias='featureTitle'; value=$title },
        @{ editorAlias='Umbraco.TextArea'; alias='featureDescription'; value=$description }
    )
}
function V-Timeline($year, $title, $description) {
    @(
        @{ editorAlias='Umbraco.TextBox'; alias='timelineYear'; value=$year },
        @{ editorAlias='Umbraco.TextBox'; alias='timelineTitle'; value=$title },
        @{ editorAlias='Umbraco.TextArea'; alias='timelineDescription'; value=$description }
    )
}

# -------------------- HOME PAGE --------------------
$homeBlocks = @(
    (New-Block 'home' 0 'heroBanner' (V-Hero 'Where Games Become a Universe' 'Welcome to Cow Paradise' 'We''re building a playful universe filled with stories, adventures, and unforgettable characters. Play, learn, and grow with the Moo Family.' 'Explore Games' '/games' 'Meet the Moo Family' '/moo-family')),
    (New-Block 'home' 1 'headingBlock' (V-Heading 'Trending Games' 'h2')),
    (New-Block 'home' 2 'richTextBlock' (V-RichText 'From racing to puzzles, our growing collection of games invites players of every age to discover Cow Paradise. Featured titles update regularly -- check back often for new adventures.')),
    (New-Block 'home' 3 'headingBlock' (V-Heading 'Meet the Moo Family' 'h2')),
    (New-Block 'home' 4 'richTextBlock' (V-RichText 'Six friendly characters lead every story -- Ellie, Little Jack, Lulu, Milo, Moo, and Tina. Each brings a unique perspective on curiosity, kindness, and play.')),
    (New-Block 'home' 5 'statBlock' (V-Stat '200K+' 'Total Downloads')),
    (New-Block 'home' 6 'statBlock' (V-Stat '98%' 'Parents Satisfaction')),
    (New-Block 'home' 7 'statBlock' (V-Stat '5+' 'Years of Experience')),
    (New-Block 'home' 8 'headingBlock' (V-Heading 'Powered by the Best in Gaming' 'h2')),
    (New-Block 'home' 9 'richTextBlock' (V-RichText 'Cow Paradise is built on industry-leading tools and platforms. We partner with the best in gaming engines, distribution, analytics, and creative tools so families get a polished experience on every device.')),
    (New-Block 'home' 10 'headingBlock' (V-Heading 'Subscribe for new stories' 'h2')),
    (New-Block 'home' 11 'newsletterSignup' (V-Newsletter 'Stay in the loop' 'Get a short email when we ship a new game, character, or story. No spam -- ever.' 'Subscribe for New Stories' 'Enter your email')),
    (New-Block 'home' 12 'headingBlock' (V-Heading 'Join the Cowverse' 'h2')),
    (New-Block 'home' 13 'ctaBlock' (V-Cta 'Join Our Community' '/moo-family' 'primary'))
)

# -------------------- ABOUT PAGE --------------------
$aboutBlocks = @(
    (New-Block 'about' 0 'heroBanner' (V-Hero 'Our Story' 'About Cow Paradise' 'From a simple sketch to a cosmic phenomenon -- the journey of Cow Paradise has been guided by one belief: that play and learning belong together.' 'Meet the Team' '#team' '' '')),
    (New-Block 'about' 1 'headingBlock' (V-Heading 'From a Simple Sketch to a Cosmic Phenomenon' 'h2')),
    (New-Block 'about' 2 'richTextBlock' (V-RichText 'Cow Paradise began with a few hand-drawn cows in a sketchbook and grew into a universe of games, stories, and characters loved by families around the world. We design every experience with kids in mind -- gentle humor, smart learning, and adventures that stick.')),
    (New-Block 'about' 3 'headingBlock' (V-Heading 'What We Stand For' 'h2')),
    (New-Block 'about' 4 'featureCard' (V-Feature '01' 'Make Learning Fun' 'We design every game and story around playful discovery, so kids learn without realizing they''re learning.')),
    (New-Block 'about' 5 'featureCard' (V-Feature '02' 'Empower Creativity' 'Our characters and worlds invite kids to imagine, build, and tell their own stories.')),
    (New-Block 'about' 6 'featureCard' (V-Feature '03' 'Foster Growth' 'Each story models curiosity, kindness, and resilience -- so kids grow alongside the Moo Family.')),
    (New-Block 'about' 7 'featureCard' (V-Feature '04' 'Build Community' 'We''re building a friendly, family-first community of parents, kids, and creators around the Cowverse.')),
    (New-Block 'about' 8 'headingBlock' (V-Heading 'Our Mission' 'h2')),
    (New-Block 'about' 9 'richTextBlock' (V-RichText 'To merge play, learning, and storytelling into one universe -- where every child feels invited to imagine, explore, and grow.')),
    (New-Block 'about' 10 'headingBlock' (V-Heading 'Our Vision' 'h2')),
    (New-Block 'about' 11 'richTextBlock' (V-RichText 'A world where children grow up surrounded by characters who teach kindness, curiosity, and the joy of trying something new.')),
    (New-Block 'about' 12 'headingBlock' (V-Heading 'From Napkin Doodles to Game Hero' 'h2')),
    (New-Block 'about' 13 'timelineItem' (V-Timeline '2022' 'The Spark' 'Cow Paradise begins as a sketchbook of friendly cow characters and a single question: what if learning felt like an adventure?')),
    (New-Block 'about' 14 'timelineItem' (V-Timeline '2023' 'Meet Atlas' 'The Moo Family universe gains its first six characters and a shared storyline that ties games and stories together.')),
    (New-Block 'about' 15 'timelineItem' (V-Timeline '2024' 'Hero Highlights' 'Cow Run launches on Google Play and crosses 200,000 downloads. Mooski enters early access; new stories ship weekly.')),
    (New-Block 'about' 16 'timelineItem' (V-Timeline '2026' 'The Big Showdown' 'Paintball Madness lands on Steam, multiplayer arrives, and the Cowverse opens its doors to a growing community of families worldwide.')),
    (New-Block 'about' 17 'headingBlock' (V-Heading 'Meet the Team' 'h2')),
    (New-Block 'about' 18 'richTextBlock' (V-RichText 'The Moo Family universe is the work of artists, engineers, and storytellers from across the world. Visit the team page to meet the people behind the cows.'))
)

# -------------------- MOO FAMILY PAGE --------------------
$mooBlocks = @(
    (New-Block 'moo' 0 'heroBanner' (V-Hero 'Meet the Moo Family' 'Friendly cows. Big adventures.' 'Six characters -- each with a unique personality -- guide the games, stories, and lessons that make Cow Paradise feel like home.' 'Browse Characters' '#characters' 'Explore Stories' '/stories')),
    (New-Block 'moo' 1 'headingBlock' (V-Heading 'A family for every kind of day' 'h2')),
    (New-Block 'moo' 2 'richTextBlock' (V-RichText 'Whether you''re feeling curious like Little Jack, brave like Lulu, or playful like Milo, there''s a Moo Family character ready to join the adventure. Learn letters, numbers, emotions, and life lessons alongside friends who care.')),
    (New-Block 'moo' 3 'headingBlock' (V-Heading 'Meet each character' 'h2')),
    (New-Block 'moo' 4 'richTextBlock' (V-RichText 'Each character has their own story, accent color, and signature moments across our games and stories. Browse the characters section above to learn what makes each one special.')),
    (New-Block 'moo' 5 'headingBlock' (V-Heading 'Learning Categories' 'h2')),
    (New-Block 'moo' 6 'richTextBlock' (V-RichText 'Six themed playlists turn every screen-time moment into a learning moment.')),
    (New-Block 'moo' 7 'featureCard' (V-Feature '01' 'Alphabet adventures' 'Trace, sing, and play your way through the alphabet alongside the Moo Family.')),
    (New-Block 'moo' 8 'featureCard' (V-Feature '02' 'ABC Puzzles' 'Match letters with friendly characters and build early-reading confidence one puzzle at a time.')),
    (New-Block 'moo' 9 'featureCard' (V-Feature '03' 'Letters seek & find' 'Hunt for hidden letters inside cheerful scenes -- a playful eye-and-mind workout.')),
    (New-Block 'moo' 10 'featureCard' (V-Feature '04' 'Candy words' 'Sweet, simple word games that grow with your child''s vocabulary.')),
    (New-Block 'moo' 11 'featureCard' (V-Feature '05' 'Bedtime Smiles' 'Calming stories and gentle activities to wind down at the end of the day.')),
    (New-Block 'moo' 12 'featureCard' (V-Feature '06' 'Brain Games' 'Logic puzzles, pattern play, and memory challenges that grow with the child.')),
    (New-Block 'moo' 13 'headingBlock' (V-Heading 'Watch the shorts' 'h2')),
    (New-Block 'moo' 14 'richTextBlock' (V-RichText 'Short animated clips starring the Moo Family -- about kindness, curiosity, and finding fun in everyday moments. New episodes added regularly to Cow Paradise Shorts.')),
    (New-Block 'moo' 15 'ctaBlock' (V-Cta 'Browse all shorts' '/stories' 'primary'))
)

# -------------------- Patch each page's blocks property --------------------
function Patch-PageBlocks($pagePath, $blocks) {
    if (-not (Test-Path $pagePath)) { Write-Warning "MISSING: $pagePath"; return }
    $json = Build-BlockListJson $blocks
    $content = [IO.File]::ReadAllText($pagePath)
    $openTag  = '<blocks>'
    $closeTag = '</blocks>'
    $startIdx = $content.IndexOf($openTag)
    $endIdx   = -1
    if ($startIdx -ge 0) { $endIdx = $content.IndexOf($closeTag, $startIdx) }
    if ($startIdx -lt 0 -or $endIdx -lt 0) { Write-Warning "tag not found in $pagePath"; return }
    $newBlock = $openTag + "`r`n      <Value><" + '![CDATA[' + $json + ']]' + "></Value>`r`n    " + $closeTag
    $patched  = $content.Substring(0, $startIdx) + $newBlock + $content.Substring($endIdx + $closeTag.Length)
    [IO.File]::WriteAllText($pagePath, $patched, [Text.UTF8Encoding]::new($false))
    Write-Host "patched $pagePath -- $($blocks.Count) blocks, $($json.Length) chars"
}

Patch-PageBlocks (Join-Path $contentRoot 'Home.config')             $homeBlocks
Patch-PageBlocks (Join-Path $contentRoot 'Home\About.config')       $aboutBlocks
Patch-PageBlocks (Join-Path $contentRoot 'Home\MooFamily.config')   $mooBlocks

# -------------------- PRIVACY POLICY --------------------
$privacyBlocks = @(
    (New-Block 'privacy' 0 'headingBlock' (V-Heading 'Privacy Policy' 'h1')),
    (New-Block 'privacy' 1 'richTextBlock' (V-RichText 'This Privacy Policy explains how Cow Paradise collects, uses, and protects your personal information when you visit our website or play our games. By using our services you agree to the practices described below.')),
    (New-Block 'privacy' 2 'headingBlock' (V-Heading 'Information we collect' 'h2')),
    (New-Block 'privacy' 3 'richTextBlock' (V-RichText 'We collect <strong>Account information</strong> (email address, display name, username), <strong>Gameplay data</strong> (game progress, achievements, in-game purchases), <strong>Analytics information</strong> (page views, clicks, session duration), <strong>Device identifiers</strong> and <strong>IP address</strong>, and <strong>Crash reports</strong> to improve stability.')),
    (New-Block 'privacy' 4 'headingBlock' (V-Heading 'How we use your information' 'h2')),
    (New-Block 'privacy' 5 'richTextBlock' (V-RichText 'We use your information to <strong>save game progress and user preferences</strong>, <strong>improve gameplay experience</strong>, <strong>display advertisements and analytics</strong>, <strong>provide customer support</strong>, <strong>prevent fraud and abuse</strong>, and <strong>comply with legal obligations</strong>.')),
    (New-Block 'privacy' 6 'headingBlock' (V-Heading 'Who we share data with' 'h2')),
    (New-Block 'privacy' 7 'richTextBlock' (V-RichText 'We share necessary data with <strong>Service providers and hosting partners</strong>, <strong>Analytics providers</strong>, <strong>Advertising and analytics partners</strong>, <strong>Payment processors</strong> and <strong>Payment providers</strong>, and <strong>Legal authorities when required</strong>. We do not sell your personal data to third parties.')),
    (New-Block 'privacy' 8 'headingBlock' (V-Heading 'Your rights' 'h2')),
    (New-Block 'privacy' 9 'richTextBlock' (V-RichText 'You have the <strong>right to access your data</strong>, the <strong>right to correction</strong>, the <strong>right to deletion</strong>, the <strong>right to object to processing</strong>, and the <strong>right to withdraw consent</strong>. Contact us at privacy@cowparadisegames.com to exercise any of these rights.')),
    (New-Block 'privacy' 10 'headingBlock' (V-Heading 'Cookies and tracking' 'h2')),
    (New-Block 'privacy' 11 'richTextBlock' (V-RichText 'We use cookies and similar technologies to remember your preferences and analyze how our services are used. You can adjust your cookie preferences in your browser settings.')),
    (New-Block 'privacy' 12 'headingBlock' (V-Heading 'Children''s privacy' 'h2')),
    (New-Block 'privacy' 13 'richTextBlock' (V-RichText 'Cow Paradise games are designed for family audiences. We do not knowingly collect personal data from children under 13 without verifiable parental consent. Parents and guardians can contact us at any time to review or delete their child''s information.')),
    (New-Block 'privacy' 14 'headingBlock' (V-Heading 'Updates to this policy' 'h2')),
    (New-Block 'privacy' 15 'richTextBlock' (V-RichText 'We may update this Privacy Policy from time to time. Significant changes will be communicated through our website or in-game notices. Last updated: 2026-05-28.'))
)

# -------------------- TERMS OF SERVICE --------------------
$termsBlocks = @(
    (New-Block 'terms' 0 'headingBlock' (V-Heading 'Terms of Service' 'h1')),
    (New-Block 'terms' 1 'richTextBlock' (V-RichText 'By accessing or using Cow Paradise games and online services, you agree to these Terms of Service. If you do not agree, please stop using our services.')),
    (New-Block 'terms' 2 'headingBlock' (V-Heading 'Your account' 'h2')),
    (New-Block 'terms' 3 'richTextBlock' (V-RichText 'You are responsible for maintaining the confidentiality of your account credentials. Notify us immediately of any unauthorized use of your account.')),
    (New-Block 'terms' 4 'headingBlock' (V-Heading 'Acceptable use' 'h2')),
    (New-Block 'terms' 5 'richTextBlock' (V-RichText 'When using Cow Paradise services you agree to: <ul><li><strong>No cheating or exploiting bugs</strong></li><li><strong>No reverse engineering</strong> of our software</li><li><strong>No resale of game assets or services</strong></li><li><strong>No harmful or abusive activities</strong> toward other players</li><li><strong>No unauthorized distribution</strong> of our content</li><li><strong>No unfair gameplay manipulation</strong></li><li><strong>No creation of derivative works</strong> without permission</li></ul>')),
    (New-Block 'terms' 6 'headingBlock' (V-Heading 'In-game purchases' 'h2')),
    (New-Block 'terms' 7 'richTextBlock' (V-RichText 'All purchases are processed by our payment providers. Virtual goods, currency, and items have no real-world cash value and are non-refundable except where required by law.')),
    (New-Block 'terms' 8 'headingBlock' (V-Heading 'Intellectual property' 'h2')),
    (New-Block 'terms' 9 'richTextBlock' (V-RichText 'All characters, artwork, software, and content of Cow Paradise are the property of Cow Paradise Games and its licensors. You may not copy, modify, or distribute them without written permission.')),
    (New-Block 'terms' 10 'headingBlock' (V-Heading 'Termination' 'h2')),
    (New-Block 'terms' 11 'richTextBlock' (V-RichText 'We may suspend or terminate accounts that violate these Terms. You may close your account at any time by contacting support@cowparadisegames.com.')),
    (New-Block 'terms' 12 'headingBlock' (V-Heading 'Disclaimers and limitation of liability' 'h2')),
    (New-Block 'terms' 13 'richTextBlock' (V-RichText 'Our services are provided "as is" without warranty. To the maximum extent permitted by law, Cow Paradise Games is not liable for indirect or consequential damages arising from use of our services.')),
    (New-Block 'terms' 14 'headingBlock' (V-Heading 'Governing law' 'h2')),
    (New-Block 'terms' 15 'richTextBlock' (V-RichText 'These Terms are governed by the laws of the jurisdiction in which Cow Paradise Games operates. Disputes will be resolved in the competent courts of that jurisdiction. Last updated: 2026-05-28.'))
)

Patch-PageBlocks (Join-Path $contentRoot 'Home\PrivacyPolicy.config')  $privacyBlocks
Patch-PageBlocks (Join-Path $contentRoot 'Home\TermsOfService.config') $termsBlocks

# -------------------- LOGIN PAGE --------------------
# Form (email, password, remember-me, submit) is rendered by the React app and processed by the app API.
# CMS owns the surrounding marketing copy, benefit cards, agreement text, and sign-up CTA.
$loginBlocks = @(
    (New-Block 'login' 0 'heroBanner' (V-Hero 'Welcome Back to Cow Paradise' 'Where Adventure Comes To Life' 'Sign in to continue your adventure with the Moo Family. Save progress, earn rewards, and join the Cowverse community.' 'Create Account' '/login?mode=signup' 'Forgot password' '/login?mode=reset')),
    (New-Block 'login' 1 'headingBlock' (V-Heading 'Why join the Cowverse?' 'h2')),
    (New-Block 'login' 2 'featureCard' (V-Feature '01' 'Save your progress' 'Pick up where you left off across every game, on every device.')),
    (New-Block 'login' 3 'featureCard' (V-Feature '02' 'Earn rewards' 'Daily quests, achievements, and chests waiting just for you.')),
    (New-Block 'login' 4 'featureCard' (V-Feature '03' 'Join the community' 'Friend lists, leaderboards, and parent-friendly multiplayer rooms.')),
    (New-Block 'login' 5 'featureCard' (V-Feature '04' 'Get early access' 'Sign-in members get first access to new games, stories, and shorts.')),
    (New-Block 'login' 6 'headingBlock' (V-Heading 'Before you continue' 'h3')),
    (New-Block 'login' 7 'richTextBlock' (V-RichText 'By signing in you agree to our <a href="/terms">Terms of Service</a> and <a href="/privacy-policy">Privacy Policy</a>. We protect your information and never sell your data.')),
    (New-Block 'login' 8 'headingBlock' (V-Heading 'New to Cow Paradise?' 'h3')),
    (New-Block 'login' 9 'richTextBlock' (V-RichText 'Creating an account takes about a minute. You''ll be asked for an email, a display name, and a password. Got a referral code from a friend? Drop it in during signup so both of you earn bonus rewards.')),
    (New-Block 'login' 10 'ctaBlock' (V-Cta 'Create an Account' '/login?mode=signup' 'primary'))
)

# -------------------- MARKET PAGE --------------------
# Actual items, prices, and inventory are managed by the admin backend (db).
# CMS owns the marketing intro, section headers, tier descriptions, and FAQ.
$marketBlocks = @(
    (New-Block 'market' 0 'heroBanner' (V-Hero 'The Cow Paradise Market' 'Power up your adventure' 'Discover items, chests, and passes that make your Cow Paradise journey richer. Items rotate weekly -- check back often for new drops.' 'Browse Items' '#shop-items' 'Battle Pass' '#battle-pass')),
    (New-Block 'market' 1 'headingBlock' (V-Heading 'Premium Items' 'h2')),
    (New-Block 'market' 2 'richTextBlock' (V-RichText 'Premium Items unlock cosmetics, gameplay boosts, and exclusive characters. Pick what fits your play-style -- each item shows its cost, daily limit, and whether it requires an active Battle Pass.')),
    (New-Block 'market' 3 'headingBlock' (V-Heading 'Shop Items' 'h2')),
    (New-Block 'market' 4 'richTextBlock' (V-RichText 'Browse the daily Shop for currency packs, time-limited gear, and seasonal collectibles. Prices and stock refresh every 24 hours.')),
    (New-Block 'market' 5 'headingBlock' (V-Heading 'Battle Pass' 'h2')),
    (New-Block 'market' 6 'richTextBlock' (V-RichText 'The Cow Paradise Battle Pass is your season-long upgrade. Unlock <strong>Premium Store Access</strong>, <strong>Premium Badge</strong>, <strong>Premium Reward</strong> tiers, and <strong>Premium Achievements</strong> as you play. Progress carries over your account across all our games.')),
    (New-Block 'market' 7 'headingBlock' (V-Heading 'Chests' 'h2')),
    (New-Block 'market' 8 'richTextBlock' (V-RichText 'Open Chests to win random rewards from one of three tiers. Higher-tier chests roll richer drop tables.')),
    (New-Block 'market' 9 'featureCard' (V-Feature '01' 'Common Reward' 'Small currency bundles, basic boosts, and starter cosmetics. Reliable, friendly, and fun.')),
    (New-Block 'market' 10 'featureCard' (V-Feature '02' 'Rare Reward' 'Mid-tier cosmetics, character skins, and Forge Time Reduction tokens. Limited but reachable with regular play.')),
    (New-Block 'market' 11 'featureCard' (V-Feature '03' 'Premium Reward' 'Top-tier items: exclusive characters, animated skins, and Win Reward multipliers. Rare drops worth chasing.')),
    (New-Block 'market' 12 'headingBlock' (V-Heading 'Privileges' 'h2')),
    (New-Block 'market' 13 'richTextBlock' (V-RichText 'Privileges grant special access in the Cowverse:')),
    (New-Block 'market' 14 'featureCard' (V-Feature '01' 'Tournament Entry' 'Enter monthly tournaments to play against the top players in Cow Paradise and win exclusive rewards.')),
    (New-Block 'market' 15 'featureCard' (V-Feature '02' 'Private Room Entry' 'Create a private multiplayer room for friends and family -- safe, ad-free, and just for you.')),
    (New-Block 'market' 16 'featureCard' (V-Feature '03' 'NFT Purchase' 'Pick up limited collectible items from special drops. NFT items are optional and never required to play.')),
    (New-Block 'market' 17 'headingBlock' (V-Heading 'Frequently asked' 'h2')),
    (New-Block 'market' 18 'richTextBlock' (V-RichText '<strong>Are purchases refundable?</strong><br>Virtual goods are non-refundable except where required by law. See our <a href="/terms">Terms of Service</a> for the full policy.<br><br><strong>Can my child make purchases?</strong><br>Purchases require an account-level confirmation. Parents and guardians can disable in-game purchases entirely in profile settings.<br><br><strong>Do items expire?</strong><br>Seasonal items expire at the end of their season. Permanent items stay in your inventory forever.')),
    (New-Block 'market' 19 'ctaBlock' (V-Cta 'Read the full terms' '/terms' 'secondary'))
)

Patch-PageBlocks (Join-Path $contentRoot 'Home\Login.config')   $loginBlocks
Patch-PageBlocks (Join-Path $contentRoot 'Home\Market.config')  $marketBlocks

Write-Host ""
Write-Host "Done. Three pages now have block content. Edit further in the backoffice block editor and export via uSync."
