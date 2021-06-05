using module "..\..\Output\Elizium.Klassy\Elizium.Klassy.psm1"

Set-StrictMode -Version 1.0

Describe 'PoShLog' -Tag 'plog' {
  BeforeAll {
    Get-Module Elizium.Klassy | Remove-Module
    Import-Module .\Output\Elizium.Klassy\Elizium.Klassy.psm1 `
      -ErrorAction 'stop' -DisableNameChecking;

    InModuleScope -ModuleName Elizium.Klassy {
      # The order of these regex matter, the most restrictive should come first.
      # They should contain the following named group reference definitions:
      #
      # * <type> -> mandatory
      # * <scope> -> optional
      # * <issue> -> optional
      #
      # It is highly recommended that the groups marked optional are present in the expressions
      # to get the best out of the tool. However, if running against a repo with low quality
      # commit messages, it may be necessary to define regex(s) that don't contain these fields.
      #
      [string[]]$script:_includes = @(
        # feat(foo)!: Add new bar (#42)
        #
        $(
          '^(?<type>fix|feat|build|chore|ci|docs|doc|style|ref|perf|test)' +
          '(?:\((?<scope>[\w]+)\))?(?<break>!)?:\s(?<body>[\w\W\s]+)(?:\(#(?<issue>\d{1,6})\))'
        )

        # feat(foo)!: #42 Add new bar
        #
        $(
          '^(?<type>fix|feat|build|chore|ci|docs|doc|style|ref|perf|test)' +
          '(?:\((?<scope>[\w]+)\))?(?<break>!)?:\s(?:#(?<issue>\d{1,6}))(?<body>[\w\W\s]+)'
        ),

        # (feat #42)!: Add new bar
        #
        $(
          '^\(?(?<type>fix|feat|build|chore|ci|docs|doc|style|ref|perf|test)' +
          '\s+(?:#(?<issue>\d{1,6}))?\)?(?<break>!)?:\s(?<body>[\w\W\s]+)'
        )
      )

      [string[]]$script:_excludes = @()
    }
  }

  BeforeEach {
    # NB: test data taken from Loopz as there are more commits there to work from
    #
    InModuleScope Elizium.Klassy {

      # The options object should be persisted to the current directory. The user
      # should run in the repo root
      #
      # Symbol references:
      # {symbol}: static symbol name or variable
      # {_X}: lookup value in 'Output' hash
      #
      [PSCustomObject]$script:_options = [PSCustomObject]@{
        PSTypeName    = 'Klassy.PoShLog.Options';
        #
        Snippet       = [PSCustomObject]@{
          PSTypeName = 'Klassy.PoShLog.Options.Snippet';
          #
          Prefix     = [PSCustomObject]@{
            PSTypeName    = 'Klassy.PoShLog.Options.Snippet.Prefix';
            #
            Conditional   = '?'; # breakStmt
            Literal       = '!'; # Anything in Output.Literals
            Lookup        = '&'; # Anything inside Output.Lookup
            NamedGroupRef = '^'; # Any named group ref inside include regex(s)
            Statement     = '*'; # Output.Statements
            Variable      = '+'; # (type, scope, change, link, tag, date, avatar) (resolved internally)
          }
        }
        Selection     = [PSCustomObject]@{
          PSTypeName          = 'Klassy.PoShLog.Options.Selection';
          #
          Order               = 'desc';
          SquashBy            = '#(?<issue>\d{1,6})'; # optional field
          Last                = $true;
          IncludeMissingIssue = $true;
          Subject             = [PSCustomObject]@{
            PSTypeName = 'Klassy.PoShLog.Options.Selection.Subject';
            #
            Include    = $_includes;
            Exclude    = $_excludes;
            Change     = '^[\w]+'; # only applied if the matching include not include 'change' named group
          }
          Tags                = [PSCustomObject]@{
            PSTypeName = 'Klassy.PoShLog.Options.Selection.Tags';
            # FROM, commits that come after the TAG
            # UNTIL, commits up to and including TAG
            #
            # In these tests, there is no default, however, when we generate
            # the default config, the default here will be Until = 'HEAD',
            # which means get everything
            #
          }
        }
        SourceControl = [PSCustomObject]@{
          PSTypeName   = 'Klassy.PoShLog.Options.SourceControl';
          #
          Name         = 'GitHub';
          HostUrl      = 'https://github.com/';
          AvatarSize   = '24';
          CommitIdSize = 7;
        }
        Output        = [PSCustomObject]@{
          PSTypeName = 'Klassy.PoShLog.Options.Output';
          #
          # special variables:
          # -> &{_A} = change => indexes into the Authors hash
          # -> &{_B} = change => indexes into the Breaking hash
          # -> &{_C} = change => indexes into the Change hash
          # -> &{_S} = scope => indexes into the Scopes hash if defined
          # -> &{_T} = type => indexes into the Types hash
          #
          Headings   = [PSCustomObject]@{ # document headings
            PSTypeName = 'Klassy.PoShLog.Options.Output.Headings';
            #
            H2         = 'Release [+{display-tag}] / +{date}';
            H3         = '*{$}'; # *{$} is translated into the correct statement from groupBy
            H4         = '*{$}';
            H5         = '*{$}';
            H6         = '*{$}';
            Dirty      = 'DIRTY: *{dirtyStmt}';
          }

          # => /#change-log/##release/###scope/####type
          # /#change-log/##release/ is fixed and can't be customised
          #
          # valid GroupBy legs are: scope/type/change/breaking, which can be specified in
          # any order. Only the first 4 map to headings H3, H4, H5 and H6
          #
          GroupBy    = 'scope/type/break/change';

          LookUp     = [PSCustomObject]@{ # => '&'
            PSTypeName     = 'Klassy.PoShLog.Options.Output.Lookup';
            #
            # => &{_A} ('_A' is a synonym of 'author')
            #
            Authors        = @{
              'plastikfan' = ':bird:';
              '?'          = ':woman_office_worker:';
            }
            # => &{_B} ('_B' is a synonym of 'break')
            # In the regex, breaking change is indicated by ! (in accordance with
            # established wisdom) and this is translated into 'breaking', and if
            # missing, 'non-breaking', hence the following loop up keys.
            #
            BreakingStatus = @{
              'breaking'     = ':warning: BREAKING CHANGES';
              'non-breaking' = ':recycle: NON BREAKING CHANGES';
            }
            # => &{_C} ('_C' is a synonym of 'change')
            #
            ChangeTypes    = @{ # The first word in the commit subject after 'type(scope): '
              'Add'       = ':heavy_plus_sign:';
              'Change'    = ':copyright:';
              'Fixed'     = ':beetle:';
              'Deprecate' = ':heavy_multiplication_x:'
              'Remove'    = ':heavy_minus_sign:';
              'Secure'    = ':key:';
              'Update'    = ':copyright:';
              '?'         = ':lock:';
            }
            # => &{_S} ('_S' is a synonym of 'scope')
            #
            Scopes         = @{
              # this is user defined. It should be maintained. Known scopes in
              # the project should be defined here
              #
              'all'     = ':star:';
              'pstools' = ':parking:';
              'remy'    = ':registered:';
              'signals' = ':triangular_flag_on_post:';
              'foo'     = ':alien:';
              'bar'     = ':space_invader:';
              'baz'     = ':bomb:';
              '?'       = ':lock:';
            }
            # => &{_T} ('_T' is a synonym of 'type')
            # (These types must be consistent with includes regex)
            #
            Types          = @{
              'fix'   = ':sparkles:';
              'feat'  = ':gift:';
              'build' = ':hammer:';
              'chore' = ':nut_and_bolt:';
              'ci'    = ':trophy:';
              'doc'   = ':clipboard:';
              'docs'  = ':clipboard:';
              'style' = ':hotsprings:';
              'ref'   = ':gem:';
              'perf'  = ':rocket:';
              'test'  = ':test_tube:';
              '?'     = ':lock:';
            }
          }
          Literals   = [PSCustomObject]@{ # => '!'
            PSTypeName    = 'Klassy.PoShLog.Options.Output.Literals';
            #
            Broken        = ':warning:';
            NotBroken     = ':recycle:';
            BucketEnd     = '---';
            DateFormat    = 'yyyy-MM-dd';
            Dirty         = ':poop:';
            Uncategorised = 'uncategorised';
          }
          Statements = [PSCustomObject]@{ # => '*'
            PSTypeName  = 'Klassy.PoShLog.Options.Output.Statements';
            #
            ActiveScope = "+{scope}";
            Author      = ' by `@+{author}` &{_A}'; # &{_A}: Author, +{avatar}: git-avatar
            Avatar      = ' by `@+{author}` +{avatar-img}';
            Break       = '!{broken} *BREAKING CHANGE* ';
            Breaking    = '&{_B}';
            Change      = '[Change Type: &{_C}+{change}] => ';
            IssueLink   = ' \<+{issue-link}\>';
            Meta        = ' (Id: +{commitid-link})?{issue-link;issueLinkStmt}'; # issue-link must be conditional
            Commit      = '+ ?{is-breaking;breakStmt}?{is-squashed;squashedStmt}*{changeStmt}*{subjectStmt}*{avatarStmt}*{metaStmt}';
            DirtyCommit = "+ ?{is-breaking;breakingStmt}+{subject}";
            Dirty       = '!{dirty}';
            Scope       = 'Scope(&{_S}?{scope;activeScopeStmt;Uncategorised})';
            Squashed    = 'SQUASHED: ';
            Subject     = 'Subject: **+{subject}**';
            Type        = 'Commit-Type(&{_T} +{type})';
            Ungrouped   = "UNGROUPED!";
          }
          Warnings   = [PSCustomObject]@{
            PSTypeName = 'Klassy.PoShLog.Options.Output.Warnings';
            Disable    = @{
              'MD253' = 'line-length';
              'MD024' = 'no-duplicate-heading/no-duplicate-header';
              'MD026' = 'no-trailing-punctuation';
              'MD033' = 'no-inline-html';
            }
          }

          Template   = $(Get-Content -Path './Tests/Data/changelog/TEMPLATE.md' -Raw);
        }
      } # $_options

      [PSCustomObject]$script:_head = [PSCustomObject]@{
        PSTypeName = 'Klassy.PoShLog.TagInfo';
        Label      = 'HEAD';
        Date       = [DateTime]::Parse('2021-04-19 18:20:49 +0100');
      }

      # === [ FakeGit ] ==============================================================
      # (can't suppress this TypeNotFound warning on SourceControl)
      # https://github.com/PowerShell/PSScriptAnalyzer/issues/1584
      #
      class FakeGit : SourceControl {
        [PSCustomObject]$_headTag;

        FakeGit([PSCustomObject]$options, [PSCustomObject]$head): base($options) {

          $this._headTag = $head;
          $this._headDate = [DateTime]::Parse('2021-04-19 18:20:49 +0100');
        }

        [PSCustomObject[]] ReadGitTags([boolean]$includeHead) {
          [PSCustomObject[]]$tags = (@(
              @('3.0.2', ([DateTime]::Parse('2021-04-19 18:17:15 +0100'))),
              @('3.0.1', ([DateTime]::Parse('2021-04-19 16:32:22 +0100'))),
              @('3.0.0', ([DateTime]::Parse('2021-04-15 19:30:42 +0100'))),
              @('2.0.0', ([DateTime]::Parse('2021-01-18 16:06:43 +0000'))),
              @('1.2.0', ([DateTime]::Parse('2020-09-17 20:07:59 +0100'))),
              @('1.1.1', ([DateTime]::Parse('2020-09-02 16:40:04 +0100'))),
              @('1.1.0', ([DateTime]::Parse('2020-08-21 19:20:22 +0100'))),
              @('1.0.1', ([DateTime]::Parse('2020-08-18 15:14:21 +0100'))),
              @('1.0.0', ([DateTime]::Parse('2020-08-18 14:44:59 +0100')))
            ) | ForEach-Object {
              [PSCustomObject]@{
                PSTypeName = 'Klassy.PoShLog.TagInfo';
                Label      = $_[0];
                Date       = $_[1];
                Version    = [system.version]::new($_[0]);
              }
            });

          if ($includeHead) {
            $tags = @(, $this._headTag) + $tags;
          }

          return $tags;
        }

        [PSCustomObject[]] ReadGitCommitsInRange(
          [string]$Format,
          [string]$Range,
          [string[]]$Header,
          [string]$Delim
        ) {
          [hashtable]$commitFeed = @{
            # 3.0.2..HEAD (unreleased)
            #
            '3.0.2..HEAD/9cadab32fd3feb3996ca933ddd2a751ae28e641a'  = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2021-04-19 18:20:49 +0100');
              CommitId   = '9cadab32fd3feb3996ca933ddd2a751ae28e641a';
              Author     = 'plastikfan';
              Subject    = "fix(foo): #999 Merge branch 'release/3.0.2'";
            };

            # 3.0.1..3.0.2
            #
            '3.0.1..3.0.2/7bd92c2e3476687311e9cb0e75218ace1a7ef5ce' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2021-04-19 18:17:15 +0100');
              CommitId   = '7bd92c2e3476687311e9cb0e75218ace1a7ef5ce';
              Author     = 'plastikfan';
              Subject    = "Bump version to 3.0.2";
            };

            '3.0.1..3.0.2/23e25cbff58be51c173bb807f49fed78ad289cdf' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2021-04-19 17:10:14 +0100');
              CommitId   = '23e25cbff58be51c173bb807f49fed78ad289cdf';
              Author     = 'plastikfan';
              Subject    = "fix(signals)!: #151 Change Test-HostSupportsEmojis to return false for mac & linux";
            }

            # 3.0.0..3.0.1
            #
            '3.0.0..3.0.1/b2eef128d0ebc3b9775675a3b6481f0eb41a79e6' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2021-04-19 16:23:44 +0100');
              CommitId   = 'b2eef128d0ebc3b9775675a3b6481f0eb41a79e6';
              Author     = 'plastikfan';
              Subject    = "Merge branch 'feature/change-command-pipeline-invocation'";
            };

            '3.0.0..3.0.1/dc800c68e4aaa6be692c8254490945ad73f69e6d' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2021-04-19 16:17:04 +0100');
              CommitId   = 'dc800c68e4aaa6be692c8254490945ad73f69e6d';
              Author     = 'plastikfan';
              Subject    = "feat(pstools): #145 Allow command to be invoked with the Name parameter instead of using pipeline";
            };

            '3.0.0..3.0.1/283093511fb2f67b4026e6b319b87acf5b2eac49' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2021-04-19 13:25:29 +0100');
              CommitId   = '283093511fb2f67b4026e6b319b87acf5b2eac49';
              Author     = 'plastikfan';
              Subject    = "chore(pstools): #147 get-CommandDetail is now an internal function";
            };

            # 2.0.0..3.0.0
            #
            '2.0.0..3.0.0/b0c917486bc71056622d22bc763abcf7687db4d5' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2021-04-15 16:57:41 +0100');
              CommitId   = 'b0c917486bc71056622d22bc763abcf7687db4d5';
              Author     = 'plastikfan';
              Subject    = "(fix #64)!: Add Trigger count to Summary";
            };

            '2.0.0..3.0.0/d227403012774896857387d9f11e7d35d36b703b' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2021-04-15 13:24:57');
              CommitId   = 'd227403012774896857387d9f11e7d35d36b703b';
              Author     = 'plastikfan';
              Subject    = "(doc #127): Minor docn tweaks";
            };

            '2.0.0..3.0.0/b055f0b43d1c0518b36b9fa48d23baeac03e55e2' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2021-04-15 12:09:19 +0100');
              CommitId   = 'b055f0b43d1c0518b36b9fa48d23baeac03e55e2';
              Author     = 'plastikfan';
              Subject    = "(doc #127): Add boostrap docn";
            };

            '2.0.0..3.0.0/b4bdc4b507f50e3a0a953ce2f167415f4fff78a0' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2021-04-15 09:53:47 +0100');
              CommitId   = 'b4bdc4b507f50e3a0a953ce2f167415f4fff78a0';
              Author     = 'plastikfan';
              Subject    = "(doc #127): Fix links in markdown";
            };

            '2.0.0..3.0.0/31277e6725a753a20d80d3504615fbdb16344a22' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2021-04-15 09:21:51 +0100');
              CommitId   = '31277e6725a753a20d80d3504615fbdb16344a22';
              Author     = 'plastikfan';
              Subject    = "(doc #127): Add docn for Test-IsAlreadyAnchoredAt";
            };

            # 1.2.0..2.0.0
            #
            '1.2.0..2.0.0/8e04f6c75325ddd7cb66303f71501ec26aac07ae' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2021-01-15 08:59:36');
              CommitId   = '8e04f6c75325ddd7cb66303f71501ec26aac07ae';
              Author     = 'plastikfan';
              Subject    = "feature/fix-select-text-env-var-not-def";
            };

            '1.2.0..2.0.0/fe2db959f9b1e8fd902b080b44a5508adeebaeb9' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2021-01-15 08:57:53');
              CommitId   = 'fe2db959f9b1e8fd902b080b44a5508adeebaeb9';
              Author     = 'plastikfan';
              Subject    = "(fix #98):Select-Patterns; When no filter supplied and LOOPZ_GREPS_FILTER not defined, default to ./*.*";
            };

            '1.2.0..2.0.0/54db603182807ef213b111519fd05b547cc5ea1e' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2021-01-14 20:20:02');
              CommitId   = '54db603182807ef213b111519fd05b547cc5ea1e';
              Author     = 'plastikfan';
              Subject    = "(fix #98): Rename Select-Text to Select-Patterns";
            };

            '1.2.0..2.0.0/193df3a22c60fe1d6a06b2cf9771968bbf0b0490' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2021-01-14 19:52:13');
              CommitId   = '193df3a22c60fe1d6a06b2cf9771968bbf0b0490';
              Author     = 'plastikfan';
              Subject    = "(doc #89): fix typos in README";
            };

            # 1.1.1..1.2.0
            #
            '1.1.1..1.2.0/7e3c5d36e0bc83bdfbab4f2f8563468fcd88aa9c' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2020-09-17 11:29:13');
              CommitId   = '7e3c5d36e0bc83bdfbab4f2f8563468fcd88aa9c';
              Author     = 'plastikfan';
              Subject    = "(fix #36): Minor controller/test improvements";
            };

            '1.1.1..1.2.0/ab3a9579019b7800c06e95f5af7e3683b321de9c' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2020-09-16 22:49:55');
              CommitId   = 'ab3a9579019b7800c06e95f5af7e3683b321de9c';
              Author     = 'plastikfan';
              Subject    = "(fix #36): Add controller tests";
            };

            '1.1.1..1.2.0/5130be22558649f5a7ba69689d7416a29b288d40' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2020-09-16 15:11:29 +0100');
              CommitId   = '5130be22558649f5a7ba69689d7416a29b288d40';
              Author     = 'plastikfan';
              Subject    = "(fix #36): Fix New-Controller parameter sets";
            };

            '1.1.1..1.2.0/e280dea7daea7ae99f7517c876f05ef138538e02' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2020-09-03 13:45:41 +0100');
              CommitId   = 'e280dea7daea7ae99f7517c876f05ef138538e02';
              Author     = 'plastikfan';
              Subject    = "(fix #34): Make tests platform friendly (break on first item)";
            };

            '1.1.1..1.2.0/22287029a3a86f1f2c9cd73433075ec8a1d543f3' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2020-09-03 12:50:33 +0100');
              CommitId   = '22287029a3a86f1f2c9cd73433075ec8a1d543f3';
              Author     = 'plastikfan';
              Subject    = "(fix #34)!: Fix Tests broken on mac";
            };

            # 1.1.0..1.1.1
            #
            '1.1.0..1.1.1/124ae0e81d4e8af762a986c24d0f8c2609f3b694' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2020-09-02 16:37:01 +0100');
              CommitId   = '124ae0e81d4e8af762a986c24d0f8c2609f3b694';
              Author     = 'plastikfan';
              Subject    = "fix Analyse task";
            };

            '1.1.0..1.1.1/fac0998be058cc00398066b333516c9aea4c61c4' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2020-08-31 11:50:59 +0100');
              CommitId   = 'fac0998be058cc00398066b333516c9aea4c61c4';
              Author     = 'plastikfan';
              Subject    = "(fix #35): Catch the MethodInvocationException";
            };

            '1.1.0..1.1.1/06d055c6a79062439596c42ecf63a0f5ee42ee8d' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2020-08-29 16:36:27 +0100');
              CommitId   = '06d055c6a79062439596c42ecf63a0f5ee42ee8d';
              Author     = 'plastikfan';
              Subject    = "Merge branch 'feature/fix-mirror-whatif";
            };

            '1.1.0..1.1.1/379aefde5a2cd10dcc6d19e2e07691e9d8c74c80' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2020-08-29 16:35:01 +0100');
              CommitId   = '379aefde5a2cd10dcc6d19e2e07691e9d8c74c80';
              Author     = 'plastikfan';
              Subject    = "(fix: #34): Use WhatIf appropriately (not on directory creation)";
            };

            '1.1.0..1.1.1/15eeb4c2098060afb68e28bf04dd88c5dbc19366' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2020-08-29 10:01:25 +0100');
              CommitId   = '15eeb4c2098060afb68e28bf04dd88c5dbc19366';
              Author     = 'plastikfan';
              Subject    = "(fix: #33): remove incorrect parameter validation on FuncteeParams";
            };

            # 1.0.1..1.1.0
            #
            '1.0.1..1.1.0/5e2b4279b0775cfa1fbf9032691ca910ed4c7979' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2020-08-21 19:13:17 +0100');
              CommitId   = '5e2b4279b0775cfa1fbf9032691ca910ed4c7979';
              Author     = 'plastikfan';
              Subject    = "(feat #24): Export functions and variables properly via psm";
            };

            '1.0.1..1.1.0/abc321c70f16627d1f657cbdee99de89f21c27c8' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2020-08-21 16:30:25 +0100');
              CommitId   = 'abc321c70f16627d1f657cbdee99de89f21c27c8';
              Author     = 'plastikfan';
              Subject    = "rename edit-RemoveSingleSubString.tests.ps1";
            };

            '1.0.1..1.1.0/fa8aea14a6b63ddd4d9c08f8f0a00edbcf9d116f' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2020-08-21 14:19:37 +0100');
              CommitId   = 'fa8aea14a6b63ddd4d9c08f8f0a00edbcf9d116f';
              Author     = 'plastikfan';
              Subject    = "Merge branch 'feature/fix-utility-globals";
            };

            '1.0.1..1.1.0/a055776bebc1c1fa7a329f7df6c6d946c17431f4' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2020-08-21 14:08:07 +0100');
              CommitId   = 'a055776bebc1c1fa7a329f7df6c6d946c17431f4';
              Author     = 'plastikfan';
              Subject    = "(feat #24): dont add files to FunctionsToExport if they are not of the form verb-noun";
            };

            # 1.0.0..1.0.1
            #
            '1.0.0..1.0.1/11120d3c4ec110123417fcb36423403486d02275' = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2020-08-18 15:14:21 +0100');
              CommitId   = '11120d3c4ec110123417fcb36423403486d02275';
              Author     = 'plastikfan';
              Subject    = "Bump version to 1.0.1";
            }

            # 1.0.0 
            #
            '1.0.0/3884bbec11f622f0c5ea8474049a891c02e0eb09'        = [PSCustomObject]@{
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Date       = [DateTime]::Parse('2020-08-17 13:59:08 +0100');
              CommitId   = '3884bbec11f622f0c5ea8474049a891c02e0eb09';
              Author     = 'plastikfan';
              Subject    = "(feat #20): Rm ITEM-VALUE/PROPERTIES; use Pairs instead; Partial check";
            }
          }


          [hashtable]$commitsByTag = @{
            '3.0.2..HEAD'  = @(
              $commitFeed['3.0.2..HEAD/9cadab32fd3feb3996ca933ddd2a751ae28e641a']
            );

            '3.0.1..3.0.2' = @(
              $commitFeed['3.0.1..3.0.2/7bd92c2e3476687311e9cb0e75218ace1a7ef5ce'],
              $commitFeed['3.0.1..3.0.2/23e25cbff58be51c173bb807f49fed78ad289cdf']
            );

            '3.0.0..3.0.1' = @(
              $commitFeed['3.0.0..3.0.1/b2eef128d0ebc3b9775675a3b6481f0eb41a79e6'],
              $commitFeed['3.0.0..3.0.1/dc800c68e4aaa6be692c8254490945ad73f69e6d'],
              $commitFeed['3.0.0..3.0.1/283093511fb2f67b4026e6b319b87acf5b2eac49']
            );

            '2.0.0..3.0.0' = @(
              $commitFeed['2.0.0..3.0.0/b0c917486bc71056622d22bc763abcf7687db4d5'],
              $commitFeed['2.0.0..3.0.0/d227403012774896857387d9f11e7d35d36b703b'],
              $commitFeed['2.0.0..3.0.0/b055f0b43d1c0518b36b9fa48d23baeac03e55e2'],
              $commitFeed['2.0.0..3.0.0/b4bdc4b507f50e3a0a953ce2f167415f4fff78a0'],
              $commitFeed['2.0.0..3.0.0/31277e6725a753a20d80d3504615fbdb16344a22']
            );

            '1.2.0..2.0.0' = @(
              $commitFeed['1.2.0..2.0.0/8e04f6c75325ddd7cb66303f71501ec26aac07ae'],
              $commitFeed['1.2.0..2.0.0/fe2db959f9b1e8fd902b080b44a5508adeebaeb9'],
              $commitFeed['1.2.0..2.0.0/54db603182807ef213b111519fd05b547cc5ea1e'],
              $commitFeed['1.2.0..2.0.0/193df3a22c60fe1d6a06b2cf9771968bbf0b0490']
            );

            '1.1.1..1.2.0' = @(
              $commitFeed['1.1.1..1.2.0/7e3c5d36e0bc83bdfbab4f2f8563468fcd88aa9c'],
              $commitFeed['1.1.1..1.2.0/ab3a9579019b7800c06e95f5af7e3683b321de9c'],
              $commitFeed['1.1.1..1.2.0/5130be22558649f5a7ba69689d7416a29b288d40'],
              $commitFeed['1.1.1..1.2.0/e280dea7daea7ae99f7517c876f05ef138538e02'],
              $commitFeed['1.1.1..1.2.0/22287029a3a86f1f2c9cd73433075ec8a1d543f3']
            );

            '1.1.0..1.1.1' = @(
              $commitFeed['1.1.0..1.1.1/124ae0e81d4e8af762a986c24d0f8c2609f3b694'],
              $commitFeed['1.1.0..1.1.1/fac0998be058cc00398066b333516c9aea4c61c4'],
              $commitFeed['1.1.0..1.1.1/06d055c6a79062439596c42ecf63a0f5ee42ee8d'],
              $commitFeed['1.1.0..1.1.1/379aefde5a2cd10dcc6d19e2e07691e9d8c74c80'],
              $commitFeed['1.1.0..1.1.1/15eeb4c2098060afb68e28bf04dd88c5dbc19366']
            );

            '1.0.1..1.1.0' = @(
              $commitFeed['1.0.1..1.1.0/5e2b4279b0775cfa1fbf9032691ca910ed4c7979'],
              $commitFeed['1.0.1..1.1.0/abc321c70f16627d1f657cbdee99de89f21c27c8'],
              $commitFeed['1.0.1..1.1.0/fa8aea14a6b63ddd4d9c08f8f0a00edbcf9d116f'],
              $commitFeed['1.0.1..1.1.0/a055776bebc1c1fa7a329f7df6c6d946c17431f4']
            );

            '1.0.0..1.0.1' = @(
              $commitFeed['1.0.0..1.0.1/11120d3c4ec110123417fcb36423403486d02275']
            );

            '1.0.0'        = @(
              $commitFeed['1.0.0/3884bbec11f622f0c5ea8474049a891c02e0eb09']
            )
          }

          [array]$commits = if ($commitsByTag.ContainsKey($Range)) {
            $commitsByTag[$Range];
          }
          else {
            throw "Failed: update commitsByTag to include range: '$Range'";
          }
          return $commits;
        }

        [string] ReadRemoteUrl() {
          return 'https://github.com/EliziumNet/Klassy'
        }
      } # FakeGit
      function script:Get-TestChangeLog {
        [OutputType([GroupBy])]
        param(
          [PSCustomObject]$Options
        )

        [SourceControl]$fakeGit = [FakeGit]::new($Options, $_head);
        [GroupByImpl]$grouper = [GroupByImpl]::new($Options);
        [MarkdownPoShLogGenerator]$generator = [MarkdownPoShLogGenerator]::new(
          $Options, $fakeGit, $grouper
        );
        [PoShLog]$changeLog = [PoShLog]::new($Options, $fakeGit, $grouper, $generator);

        [PSCustomObject]$dependencies = [PSCustomObject]@{
          PSTypeName    = 'Klassy.PoShLog.Test.Dependencies'
          #
          SourceControl = $fakeGit;
          Grouper       = $grouper;
          Generator     = $generator;
        }

        return $changeLog, $dependencies;
      }

      [PoShLog]$script:_changeLog, $null = Get-TestChangeLog -Options $_options;

      function script:Show-Releases {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
        param(
          [hashtable]$Releases,
          [PoShLog]$changer
        )

        [int]$squashedCount = 0;
        [int]$commitsCount = 0;

        Write-Host "===> found '$($Releases.PSBase.Count)' releases with commits";

        $Releases.PSBase.Keys | Sort-Object -Descending | ForEach-Object {

          Write-host "    ~~~ RELEASE: '$_' ~~~";
          Write-Host "";
          [string]$tag = $_.ToString();
          [PSCustomObject]$releaseObj = $Releases[$tag];

          if ($releaseObj) {
            if (${releaseObj}?.Squashed) {
              $squashedCount = $releaseObj.Squashed.PSBase.Count;

              [string[]]$keys = $releaseObj.Squashed.PSBase.Keys
              foreach ($issue in $keys) {
                $squashedItem = $releaseObj.Squashed[$issue];

                if ($squashedItem -is [System.Collections.Generic.List[PSCustomObject]]) {
                  foreach ($squashed in $squashedItem) {
                    Write-Host "      --- SQUASHED COMMIT ($issue): '$($squashed.Subject)'";
                  }
                }
                else {
                  Write-Host "      +++ UN-SQUASHED COMMIT ($issue): '$($squashedItem.Subject)'";
                }
              }
            }

            if (${releaseObj}?.Commits) {
              $commitsCount = $releaseObj.Commits.Count;

              foreach ($comm in $releaseObj.Commits) {
                Write-Host "      /// OTHER COMMIT: '$($comm.Subject)'";
              }
            }

            Write-Host "    >>> Tag (until): '$_', Squashed: '$squashedCount', commitsCount: '$commitsCount'"

            if ($changer) {
              $changer.CountCommits
            }
          }
          Write-Host "";
        }
      }
    }
  }

  Context 'GetTagsInRange' {
    Context 'given: OrderBy descending' {
      Context 'and: full history (no tags defined)' {
        It 'should: return all tags' {
          InModuleScope Elizium.Klassy {
            $_changeLog.Init();
            [PSCustomObject[]]$result = $_changeLog.GetTagsInRange();
            $result.Count | Should -Be 10;

            $result[1].Version.CompareTo([system.version]::new(3, 0, 2)) | Should -Be 0;
            $result[9].Version.CompareTo([system.version]::new(1, 0, 0)) | Should -Be 0;
          }
        }
      } # and: full history

      Context 'and: full history (until = HEAD)' {
        It 'should: return all tags' {
          InModuleScope Elizium.Klassy {
            $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
              Until = 'HEAD';
            }
            $_changeLog.Init();

            [PSCustomObject[]]$result = $_changeLog.GetTagsInRange();
            $result.Count | Should -Be 10;

            $result[1].Version.CompareTo([system.version]::new(3, 0, 2)) | Should -Be 0;
            $result[9].Version.CompareTo([system.version]::new(1, 0, 0)) | Should -Be 0;
          }
        }
      } # and: full history (until = HEAD)

      Context 'and: un-released' {
        It 'should: return last release' {
          InModuleScope Elizium.Klassy {
            $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
              Unreleased = $true;
            }
            $_changeLog.Init();

            [PSCustomObject[]]$result = $_changeLog.GetTagsInRange();
            $result.Count | Should -Be 1;
            $result[0].Label | Should -BeExactly 'HEAD';
          }
        }
      } # and: un-released

      Context 'and: since specified tag' {
        It 'should: return tags since' {
          InModuleScope Elizium.Klassy {
            $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
              From = '3.0.0';
            }
            $_changeLog.Init();

            [PSCustomObject[]]$result = $_changeLog.GetTagsInRange();
            $result.Count | Should -Be 4;
            $result[1].Version.CompareTo([system.version]::new(3, 0, 2)) | Should -Be 0;
            $result[3].Version.CompareTo([system.version]::new(3, 0, 0)) | Should -Be 0;
          }
        }
      } # and: since specified tag

      Context 'and: until specified tag' {
        It 'should: return tags until' {
          InModuleScope Elizium.Klassy {
            $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
              Until = '3.0.0';
            }
            $_changeLog.Init();

            [PSCustomObject[]]$result = $_changeLog.GetTagsInRange();
            $result.Count | Should -Be 7;
            $result[0].Version.CompareTo([system.version]::new(3, 0, 0)) | Should -Be 0;
            $result[6].Version.CompareTo([system.version]::new(1, 0, 0)) | Should -Be 0;
          }
        }
      } # and: until specified tag

      Context 'and: between 2 specified tags' {
        It 'should: return tags in range' {
          InModuleScope Elizium.Klassy {
            $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
              From  = '3.0.0';
              Until = '3.0.2';
            }
            $_changeLog.Init();

            [PSCustomObject[]]$result = $_changeLog.GetTagsInRange();
            $result.Count | Should -Be 3;
            $result[0].Version.CompareTo([system.version]::new(3, 0, 2)) | Should -Be 0;
            $result[2].Version.CompareTo([system.version]::new(3, 0, 0)) | Should -Be 0;
          }
        }


        It 'should: return tags in range' {
          InModuleScope Elizium.Klassy {
            $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
              From  = '1.1.1';
              Until = '1.2.0';
            }
            $_changeLog.Init();

            [PSCustomObject[]]$result = $_changeLog.GetTagsInRange();
            $result.Count | Should -Be 2;
            $result[0].Version.CompareTo([system.version]::new(1, 2, 0)) | Should -Be 0;
            $result[1].Version.CompareTo([system.version]::new(1, 1, 1)) | Should -Be 0;
          }
        }

        It 'should: return tags in range' {
          InModuleScope Elizium.Klassy {
            $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
              Until = '1.0.0';
            }
            $_changeLog.Init();

            [PSCustomObject[]]$result = $_changeLog.GetTagsInRange();
            $result.Count | Should -Be 1;
            $result[0].Version.CompareTo([system.version]::new(1, 0, 0)) | Should -Be 0;
          }
        }
      } # and: between 2 specified tags
    } # given: OrderBy descending
  } # GetTagsInRange

  Context 'getRange' {
    BeforeEach {
      InModuleScope Elizium.Klassy {
        function initialize-WithTagIndices {
          #     0,     1,     2,     3,     4,     5,     6,     7,     8
          # 3.0.2, 3.0.1, 3.0.0, 2.0.0, 1.2.0, 1.1.1, 1.1.0, 1.0.1, 1.0.0
          #
          [OutputType([hashtable])]
          param(
            [PoShLog]$changeLog
          )
          $changeLog.Init();

          [array]$tagsInRange = $_changeLog.TagsInRangeWithHead;
          [hashtable]$indexOfTag = @{};

          [string[]]$labelSequence = $tagsInRange.Label;
          [int]$counter = 0;

          $labelSequence | ForEach-Object {
            $indexOfTag[$_] = $counter++; 
          }

          return [PSCustomObject]@{
            IndexOfTag  = $indexOfTag;
            TagsInRange = $tagsInRange;
          }
        }

        [PSCustomObject]$_result = initialize-WithTagIndices -changeLog $_changeLog;
        [hashtable]$script:_indexOfTag = $_result.IndexOfTag;
        [array]$script:_tagsInRange = $_result.TagsInRange;
      }
    }

    Context 'given: OrderBy descending' {
      Context 'and: current is HEAD' {
        It 'should: return correct range latest to HEAD' {
          InModuleScope Elizium.Klassy {
            [PSCustomObject]$current = $_head;

            $_changeLog.getRange($current, $_tagsInRange).Range | Should -BeExactly '3.0.2..HEAD';
          }
        }
      } # and: full history

      Context 'and: current is earliest tag' {
        It 'should: return current by itself' {
          InModuleScope Elizium.Klassy {
            [PSCustomObject]$current = $_tagsInRange[$_indexOfTag['1.0.0']];

            $_changeLog.getRange($current, $_tagsInRange).Range | Should -BeExactly '1.0.0';
          }
        }
      }

      Context 'and: current is midway through tag sequence' {
        It 'should: return current as until, and the previous (earlier) as from' {
          InModuleScope Elizium.Klassy {
            [PSCustomObject]$current = $_tagsInRange[$_indexOfTag['1.2.0']];

            $_changeLog.getRange($current, $_tagsInRange).range | Should -BeExactly '1.1.1..1.2.0';
          }
        }
      }
    } # given: OrderBy descending
  } #getRange

  Describe 'Tag Validation' {
    Context 'given: Unreleased specified' {
      Context 'and: From is present' {
        It 'should: throw' {
          InModuleScope Elizium.Klassy {
            {
              $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
                Until      = '1.0.0';
                Unreleased = $true;
              }
              $_changeLog.Init();
            } | Should -Throw;
          }
        }
      }

      Context 'and: Until is present' {
        It 'should: throw' {
          InModuleScope Elizium.Klassy {
            {
              $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
                From       = '1.0.0';
                Unreleased = $true;
              }
              $_changeLog.Init();
            } | Should -Throw;
          }
        }
      }
    }

    Context 'given: unknown tag is specified' {
      It 'should: throw' {
        InModuleScope Elizium.Klassy {
          {
            $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
              From = '1.0.0-blooper';
            }
            $_changeLog.Init();
          } | Should -Throw;
        }
      }
    }

    Context 'given: From and Until specified in wrong order' {
      It 'should: throw' {
        InModuleScope Elizium.Klassy {
          {
            $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
              From  = '3.0.0';
              Until = '1.0.0';
            }
            $_changeLog.Init();
          } | Should -Throw;          
        }
      }
    }
  }

  Context 'processCommits' {
    Context 'given: SquashBy enabled' {
      Context 'given: OrderBy descending' {
        Context 'and: IncludeMissingIssue enabled' {
          Context 'given: full history (no tags defined)' {
            It 'should: return commits for all tags' -Tag 'Pending' {
              InModuleScope Elizium.Klassy {
                $_changeLog.Init();

                [hashtable]$releases = $_changeLog.processCommits();
                # Show-Releases -Releases $releases;

                $releases.PSBase.Count | Should -Be 10;
                $releases['HEAD'].Squashed['999'].Subject | `
                  Should -BeExactly "fix(foo): #999 Merge branch 'release/3.0.2'";
              }
            }
          } # given: full history (no tags defined)

          Context 'given: full history (until = HEAD)' {
            It 'should: return commits for all tags' {
              InModuleScope Elizium.Klassy {
                $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
                  Until = 'HEAD';
                }
                $_changeLog.Init();

                [hashtable]$releases = $_changeLog.processCommits();

                $releases.PSBase.Count | Should -Be 10;
                $releases['HEAD'].Squashed['999'].Subject | `
                  Should -BeExactly "fix(foo): #999 Merge branch 'release/3.0.2'";
              }
            }
          } # given: full history (until = HEAD)

          Context 'and: un-released' {
            It 'should: return commits since last release' {
              InModuleScope Elizium.Klassy {
                $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
                  Unreleased = $true;
                }
                $_changeLog.Init();

                [hashtable]$releases = $_changeLog.processCommits();
                $releases.PSBase.Count | Should -Be 1;
                # Un-squashed
                #
                $releases['HEAD'].Squashed['999'].Subject | `
                  Should -BeExactly "fix(foo): #999 Merge branch 'release/3.0.2'";
              }
            }
          } # and: un-released

          Context 'and: since specified tag' {
            It 'should: return commits since' {
              InModuleScope Elizium.Klassy {
                $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
                  From = '3.0.0';
                }
                $_changeLog.Init();

                [hashtable]$releases = $_changeLog.processCommits();
                $releases.PSBase.Count | Should -Be 4;
                # Un-Squashed
                #
                $releases['HEAD'].Squashed['999'].Subject | `
                  Should -BeExactly "fix(foo): #999 Merge branch 'release/3.0.2'";
                $releases['3.0.2'].Squashed['151'].Subject | `
                  Should -BeExactly "fix(signals)!: #151 Change Test-HostSupportsEmojis to return false for mac & linux";
                $releases['3.0.1'].Squashed['145'].Subject | `
                  Should -BeExactly "feat(pstools): #145 Allow command to be invoked with the Name parameter instead of using pipeline";
                $releases['3.0.1'].Squashed['147'].Subject | `
                  Should -BeExactly "chore(pstools): #147 get-CommandDetail is now an internal function";
              }
            }
          } # and: since specified tag

          Context 'and: until specified tag' {
            It 'should: return commits until' {
              InModuleScope Elizium.Klassy {
                $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
                  Until = '3.0.0';
                }
                $_changeLog.Init();

                [hashtable]$releases = $_changeLog.processCommits();
                $releases.PSBase.Count | Should -Be 7;
                # Releases that are verified in other tests are omitted for brevity
                # (3.0.0 and 1.2.0)

                # Un-Squashed
                #
                $releases['1.1.1'].Squashed['35'].Subject | `
                  Should -BeExactly "(fix #35): Catch the MethodInvocationException";

                $releases['2.0.0'].Squashed['98'].Subject | `
                  Should -BeExactly "(fix #98): Rename Select-Text to Select-Patterns";

                $releases['2.0.0'].Squashed['89'].Subject | `
                  Should -BeExactly "(doc #89): fix typos in README";

                # Squashed
                #
                [array]$squashed24 = $releases['1.1.0'].Squashed['24'];
                $squashed24.Count | Should -Be 2;

                [string[]]$subjects24 = $squashed24.Subject;
                $subjects24 | `
                  Should -Contain '(feat #24): Export functions and variables properly via psm';
                $subjects24 | `
                  Should -Contain '(feat #24): dont add files to FunctionsToExport if they are not of the form verb-noun';
              }
            }
          } # and: until specified tag

          Context 'and: between 2 specified tags' {
            It 'should: return commits in range' {
              InModuleScope Elizium.Klassy {
                $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
                  From  = '3.0.0';
                  Until = '3.0.2';
                }
                $_changeLog.Init();

                [hashtable]$releases = $_changeLog.processCommits();
                $releases.PSBase.Count | Should -Be 3;
                # Un-squashed
                #
                $releases['3.0.2'].Squashed['151'].Subject | `
                  Should -BeExactly "fix(signals)!: #151 Change Test-HostSupportsEmojis to return false for mac & linux";

                $releases['3.0.1'].Squashed['145'].Subject | `
                  Should -BeExactly "feat(pstools): #145 Allow command to be invoked with the Name parameter instead of using pipeline";

                $releases['3.0.1'].Squashed['147'].Subject | `
                  Should -BeExactly "chore(pstools): #147 get-CommandDetail is now an internal function";
              }
            }

            It 'should: return commits in range' {
              InModuleScope Elizium.Klassy {
                $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
                  From  = '1.1.1';
                  Until = '1.2.0';
                }
                $_changeLog.Init();

                [hashtable]$releases = $_changeLog.processCommits();
                $releases.PSBase.Count | Should -Be 2;
                # Squashed
                #
                [array]$squashed34 = $releases['1.2.0'].Squashed['34'];
                [array]$squashed36 = $releases['1.2.0'].Squashed['36'];
                $squashed34.Count | Should -Be 2;
                $squashed36.Count | Should -Be 3;

                [string[]]$subjects34 = $squashed34.Subject;
                $subjects34 | Should -Contain '(fix #34): Make tests platform friendly (break on first item)';
                $subjects34 | Should -Contain '(fix #34)!: Fix Tests broken on mac';

                [string[]]$subjects36 = $squashed36.Subject;
                $subjects36 | Should -Contain '(fix #36): Minor controller/test improvements';
                $subjects36 | Should -Contain '(fix #36): Add controller tests';
                $subjects36 | Should -Contain '(fix #36): Fix New-Controller parameter sets';
              }
            }

            It 'should: return commits in range' {
              InModuleScope Elizium.Klassy {
                $_changeLog.Options.Selection.Tags = [PSCustomObject]@{
                  From  = '2.0.0';
                  Until = '3.0.0';
                }
                $_changeLog.Init();

                [hashtable]$releases = $_changeLog.processCommits();
                $releases.PSBase.Count | Should -Be 2;
                # Squashed
                #
                [array]$squashed127 = $releases['3.0.0'].Squashed['127'];
                $squashed127.Count | Should -Be 4;

                [string[]]$subjects127 = $squashed127.Subject;
                $subjects127 | Should -Contain '(doc #127): Minor docn tweaks';
                $subjects127 | Should -Contain '(doc #127): Add boostrap docn';
                $subjects127 | Should -Contain '(doc #127): Fix links in markdown';
                $subjects127 | Should -Contain '(doc #127): Add docn for Test-IsAlreadyAnchoredAt';

                # Un-Squashed
                #
                $releases['3.0.0'].Squashed['64'].Subject | `
                  Should -BeExactly "(fix #64)!: Add Trigger count to Summary";
              }
            }
          } # and: between 2 specified tags
        } # and: IncludeMissingIssue enabled
      } # given: OrderBy descending
    } # given: SquashBy enabled

    Context 'given: SquashBy NOT enabled' {
      Context 'given: OrderBy descending' {
        Context 'given: full history (no tags defined)' {
          It 'should: return commits for all tags' {
            InModuleScope Elizium.Klassy {
              $_options.Selection.SquashBy = [string]::Empty;
              [PoShLog]$changeLog, $null = Get-TestChangeLog -Options $_options;
              $changeLog.Init();

              [hashtable]$releases = $changeLog.processCommits();
              $releases.PSBase.Count | Should -Be 10;

              $releases['HEAD'].Commits.Count | Should -Be 1;
              $releases['3.0.2'].Commits.Count | Should -Be 1;
              $releases['3.0.1'].Commits.Count | Should -Be 2;
              $releases['3.0.0'].Commits.Count | Should -Be 5;
              $releases['2.0.0'].Commits.Count | Should -Be 2;
              $releases['1.2.0'].Commits.Count | Should -Be 5;
              $releases['1.1.1'].Commits.Count | Should -Be 1;
              $releases['1.1.0'].Commits.Count | Should -Be 2;
              $releases['1.0.1'].Commits.Count | Should -Be 0; # (subject: "Bump version to 1.0.1")
            }
          } # should: return commits for all tags
        } # given: full history (no tags defined)
      } # given: OrderBy descending
    } # given: SquashBy NOT enabled
  } # processCommits

  Context 'composePartitions' {
    Context 'and: full history (no tags defined)' {
      Context 'given: GroupBy path: scope/type' {
        It 'should: compose change log partitions' {
          InModuleScope Elizium.Klassy {
            $_options.Output.GroupBy = 'scope/type';
            [PoShLog]$changeLog, $null = Get-TestChangeLog -Options $_options;
            $changeLog.Init();

            [array]$releases = $changeLog.composePartitions();
            Write-Debug "=== Built '$($releases.Count)' releases (path: '$($changeLog.Options.Output.GroupBy)')";

            $releases.Count | Should -Be 10;

            $releases[0].Tag.Label | Should -Be 'HEAD';
            $releases[0].Partitions['foo']['fix'].Count | Should -Be 1;
            $releases[0].Partitions['foo']['fix'][0].Subject.StartsWith('fix(foo): #999') | Should -BeTrue;

            $releases[1].Tag.Label | Should -Be '3.0.2';
            $releases[1].Partitions['signals']['fix'].Count | Should -Be 1;
            $releases[1].Partitions['signals']['fix'][0].Subject.StartsWith('fix(signals)!: #151') | Should -BeTrue;

            $releases[2].Tag.Label | Should -Be '3.0.1';
            $releases[2].Partitions['pstools']['feat'].Count | Should -Be 1;
            $releases[2].Partitions['pstools']['feat'][0].Subject.StartsWith('feat(pstools): #145') | Should -BeTrue;
            $releases[2].Partitions['pstools']['chore'].Count | Should -Be 1;
            $releases[2].Partitions['pstools']['chore'][0].Subject.StartsWith('chore(pstools): #147') | Should -BeTrue;

            $releases[3].Tag.Label | Should -Be '3.0.0';
            $releases[3].Partitions['uncategorised']['fix'].Count | Should -Be 1;
            $releases[3].Partitions['uncategorised']['fix'][0].Subject.StartsWith('(fix #64)!:') | Should -BeTrue;
            $releases[3].Partitions['uncategorised']['doc'].Count | Should -Be 1;
            $releases[3].Partitions['uncategorised']['doc'][0].Subject.StartsWith('(doc #127):') | Should -BeTrue;

            $releases[4].Tag.Label | Should -Be '2.0.0';
            $releases[4].Partitions['uncategorised']['fix'].Count | Should -Be 1;
            $releases[4].Partitions['uncategorised']['fix'][0].Subject.StartsWith('(fix #98):') | Should -BeTrue;
            $releases[4].Partitions['uncategorised']['doc'].Count | Should -Be 1;
            $releases[4].Partitions['uncategorised']['doc'][0].Subject.StartsWith('(doc #89):') | Should -BeTrue;

            $releases[5].Tag.Label | Should -Be '1.2.0';
            $releases[5].Partitions['uncategorised']['fix'].Count | Should -Be 2;
            $releases[5].Partitions['uncategorised']['fix'] | Where-Object { # Can't rely on order, so search!
              $_.Subject.StartsWith('(fix #36):')
            } | Should -Not -BeNullOrEmpty;
            $releases[5].Partitions['uncategorised']['fix'] | Where-Object {
              $_.Subject.StartsWith('(fix #34)!:')
            } | Should -Not -BeNullOrEmpty;

            $releases[6].Tag.Label | Should -Be '1.1.1';
            $releases[6].Partitions['uncategorised']['fix'].Count | Should -Be 1;
            $releases[6].Partitions['uncategorised']['fix'][0].Subject.StartsWith('(fix #35):') | Should -BeTrue;

            $releases[7].Tag.Label | Should -Be '1.1.0';
            $releases[7].Partitions['uncategorised']['feat'].Count | Should -Be 1;
            $releases[7].Partitions['uncategorised']['feat'][0].Subject.StartsWith('(feat #24):') | Should -BeTrue;

            $releases[8].Tag.Label | Should -Be '1.0.1';
            $releases[8].Partitions['dirty'].Count | Should -Be 1;
            $releases[8].Partitions['dirty'][0].Subject.StartsWith('Bump version') | Should -BeTrue;
          }
        } # should: compose change log partitions
      } # given: GroupBy path: scope/type

      Context 'given: GroupBy path: type/scope' {
        It 'should: compose change log partitions' {
          InModuleScope Elizium.Klassy {
            $_options.Output.GroupBy = 'type/scope';
            [PoShLog]$changeLog, $null = Get-TestChangeLog -Options $_options;
            $changeLog.Init();

            [array]$releases = $changeLog.composePartitions();
            Write-Debug "=== Built '$($releases.Count)' releases (path: '$($changeLog.Options.Output.GroupBy)')";

            $releases.Count | Should -Be 10;

            $releases[0].Tag.Label | Should -Be 'HEAD';
            $releases[0].Partitions['fix']['foo'].Count | Should -Be 1;
            $releases[0].Partitions['fix']['foo'][0].Subject.StartsWith('fix(foo): #999') | Should -BeTrue;

            $releases[1].Tag.Label | Should -Be '3.0.2';
            $releases[1].Partitions['fix']['signals'].Count | Should -Be 1;
            $releases[1].Partitions['fix']['signals'][0].Subject.StartsWith('fix(signals)!: #151') | Should -BeTrue;

            $releases[2].Tag.Label | Should -Be '3.0.1';
            $releases[2].Partitions['feat']['pstools'].Count | Should -Be 1;
            $releases[2].Partitions['feat']['pstools'][0].Subject.StartsWith('feat(pstools): #145') | Should -BeTrue;
            $releases[2].Partitions['chore']['pstools'].Count | Should -Be 1;
            $releases[2].Partitions['chore']['pstools'][0].Subject.StartsWith('chore(pstools): #147') | Should -BeTrue;

            $releases[3].Tag.Label | Should -Be '3.0.0';
            $releases[3].Partitions['fix']['uncategorised'].Count | Should -Be 1;
            $releases[3].Partitions['fix']['uncategorised'][0].Subject.StartsWith('(fix #64)!:') | Should -BeTrue;
            $releases[3].Partitions['doc']['uncategorised'].Count | Should -Be 1;
            $releases[3].Partitions['doc']['uncategorised'][0].Subject.StartsWith('(doc #127):') | Should -BeTrue;

            $releases[4].Tag.Label | Should -Be '2.0.0';
            $releases[4].Partitions['fix']['uncategorised'].Count | Should -Be 1;
            $releases[4].Partitions['fix']['uncategorised'][0].Subject.StartsWith('(fix #98):') | Should -BeTrue;
            $releases[4].Partitions['doc']['uncategorised'].Count | Should -Be 1;
            $releases[4].Partitions['doc']['uncategorised'][0].Subject.StartsWith('(doc #89):') | Should -BeTrue;

            $releases[5].Tag.Label | Should -Be '1.2.0';
            $releases[5].Partitions['fix']['uncategorised'].Count | Should -Be 2;
            $releases[5].Partitions['fix']['uncategorised'] | Where-Object { # Can't rely on order, so search!
              $_.Subject.StartsWith('(fix #36):')
            } | Should -Not -BeNullOrEmpty;
            $releases[5].Partitions['fix']['uncategorised'] | Where-Object {
              $_.Subject.StartsWith('(fix #34)!:')
            } | Should -Not -BeNullOrEmpty;

            $releases[6].Tag.Label | Should -Be '1.1.1';
            $releases[6].Partitions['fix']['uncategorised'].Count | Should -Be 1;
            $releases[6].Partitions['fix']['uncategorised'][0].Subject.StartsWith('(fix #35):') | Should -BeTrue;

            $releases[7].Tag.Label | Should -Be '1.1.0';
            $releases[7].Partitions['feat']['uncategorised'].Count | Should -Be 1;
            $releases[7].Partitions['feat']['uncategorised'][0].Subject.StartsWith('(feat #24):') | Should -BeTrue;

            $releases[8].Tag.Label | Should -Be '1.0.1';
            $releases[8].Partitions['dirty'].Count | Should -Be 1;
            $releases[8].Partitions['dirty'][0].Subject.StartsWith('Bump version') | Should -BeTrue;
          }
        }
      } # given: GroupBy path: type/scope

      Context 'given: GroupBy path: type' {
        It 'should: compose change log partitions' {
          InModuleScope Elizium.Klassy {
            $_options.Output.GroupBy = 'type';
            [PoShLog]$changeLog, $null = Get-TestChangeLog -Options $_options;
            $changeLog.Init();

            [array]$releases = $changeLog.composePartitions();
            Write-Debug "=== Built '$($releases.Count)' releases (path: '$($changeLog.Options.Output.GroupBy)')";

            $releases.Count | Should -Be 10;

            $releases[0].Tag.Label | Should -Be 'HEAD';
            $releases[0].Partitions['fix'].Count | Should -Be 1;
            $releases[0].Partitions['fix'][0].Subject.StartsWith('fix(foo): #999') | Should -BeTrue;

            $releases[1].Tag.Label | Should -Be '3.0.2';
            $releases[1].Partitions['fix'].Count | Should -Be 1;
            $releases[1].Partitions['fix'][0].Subject.StartsWith('fix(signals)!: #151') | Should -BeTrue;

            $releases[2].Tag.Label | Should -Be '3.0.1';
            $releases[2].Partitions['feat'].Count | Should -Be 1;
            $releases[2].Partitions['feat'][0].Subject.StartsWith('feat(pstools): #145') | Should -BeTrue;
            $releases[2].Partitions['chore'].Count | Should -Be 1;
            $releases[2].Partitions['chore'][0].Subject.StartsWith('chore(pstools): #147') | Should -BeTrue;

            # ...
            #
          }
        }
      } # given: GroupBy path: type

      Context 'given: GroupBy path: scope' {
        It 'should: compose change log partitions' {
          InModuleScope Elizium.Klassy {
            $_options.Output.GroupBy = 'scope';
            [PoShLog]$changeLog, $null = Get-TestChangeLog -Options $_options;
            $changeLog.Init();

            [array]$releases = $changeLog.composePartitions();
            Write-Debug "=== Built '$($releases.Count)' releases (path: '$($changeLog.Options.Output.GroupBy)')";

            $releases.Count | Should -Be 10;

            #
            # ...

            $releases[6].Tag.Label | Should -Be '1.1.1';
            $releases[6].Partitions['uncategorised'].Count | Should -Be 1;
            $releases[6].Partitions['uncategorised'][0].Subject.StartsWith('(fix #35):') | Should -BeTrue;

            $releases[7].Tag.Label | Should -Be '1.1.0';
            $releases[7].Partitions['uncategorised'].Count | Should -Be 1;
            $releases[7].Partitions['uncategorised'][0].Subject.StartsWith('(feat #24):') | Should -BeTrue;

            $releases[8].Tag.Label | Should -Be '1.0.1';
            $releases[8].Partitions['dirty'].Count | Should -Be 1;
            $releases[8].Partitions['dirty'][0].Subject.StartsWith('Bump version') | Should -BeTrue;
          }
        } # should: compose change log partitions
      } # given: GroupBy path: scope

      Context 'given: GroupBy path: nothing' {
        It 'should: compose change log partitions' {
          InModuleScope Elizium.Klassy {
            $_options.Output.GroupBy = [string]::Empty;
            [PoShLog]$changeLog, $null = Get-TestChangeLog -Options $_options;
            $changeLog.Init();

            [array]$releases = $changeLog.composePartitions();
            Write-Debug "=== Built '$($releases.Count)' releases (path: '$($changeLog.Options.Output.GroupBy)')";

            $releases.Count | Should -Be 10;

            $releases[0].Tag.Label | Should -Be 'HEAD';
            $releases[0].Partitions['uncategorised'].Count | Should -Be 1;
            $releases[0].Partitions['uncategorised'][0].Subject.StartsWith('fix(foo): #999') | Should -BeTrue;

            # ...
            #
          }
        }
      } # given: GroupBy path: nothing
    } # and: full history (no tags defined)

    Context 'Output' {
      BeforeEach {
        InModuleScope Elizium.Klassy {
          [scriptblock]$script:_OnCommit = {
            [OutputType([string])]
            param(
              [PSTypeName('Klassy.PoShLog.SegmentInfo')]$segmentInfo,
              [PSTypeName('Klassy.PoShLog.CommitInfo')]$commit,
              [PSTypeName('Klassy.PoShLog.TagInfo')]$tagInfo,
              [PSCustomObject]$custom
            )

            Write-Debug $(
              "OnCommit: path: '$($segmentInfo.Path)', subject: '$($commit.Subject)'" +
              ", Tag: '$($tagInfo.Label)', Dirty: '$($segmentInfo.IsDirty)'"
            );
          }

          [scriptblock]$script:_OnEndBucket = {
            [OutputType([string])]
            param(
              [PSTypeName('Klassy.PoShLog.SegmentInfo')]$segmentInfo,
              [PSTypeName('Klassy.PoShLog.TagInfo')]$tagInfo,
              [GeneratorUtils]$utils,
              [PSTypeName('Klassy.PoShLog.WalkInfo')]$custom
            )
            Write-Debug $("OnEndBucket: decorated path: '$($segmentInfo.DecoratedPath)'");
          }

          [scriptblock]$script:_OnHeading = {
            [OutputType([string])]
            param(
              [string]$headingType,
              [string]$headingFormat,
              [PSTypeName('Klassy.PoShLog.SegmentInfo')]$segmentInfo,
              [PSTypeName('Klassy.PoShLog.TagInfo')]$tagInfo,
              [GeneratorUtils]$utils,
              [PSTypeName('Klassy.PoShLog.WalkInfo')]$custom
            )
            Write-Debug $("OnHeading('$($headingType)'): decorated path: '$($segmentInfo.DecoratedPath)'");
          }

          [PSCustomObject]$script:_handlers = [PSCustomObject]@{
            PSTypeName = 'Klassy.PoShLog.Handlers';
          }

          $_handlers | Add-Member -MemberType ScriptMethod -Name 'OnHeading' -Value $(
            $_OnHeading
          );

          $_handlers | Add-Member -MemberType ScriptMethod -Name 'OnCommit' -Value $(
            $_OnCommit
          );

          $_handlers | Add-Member -MemberType ScriptMethod -Name 'OnEndBucket' -Value $(
            $_OnEndBucket
          );
        }
      } # BeforeEach

      Context 'GroupBy.Walk' {
        Context 'given: full history (no tags defined)' {
          Context 'and: GroupBy path: scope/type' {
            It 'should: compose change log partitions' {
              InModuleScope Elizium.Klassy {
                $_options.Output.GroupBy = 'scope/type';

                [PoShLog]$changeLog, [PSCustomObject]$dependencies = Get-TestChangeLog -Options $_options;
                $changeLog.Init();

                [array]$releases = $changeLog.composePartitions();
                [PSCustomObject]$customWalkInfo = [PSCustomObject]@{
                  PSTypeName = 'Klassy.PoShLog.WalkInfo';
                  #
                  Appender   = [LineAppender]::new()
                  Options    = $_options;
                }

                foreach ($release in $releases) {
                  $dependencies.Grouper.Walk($release, $_handlers, $customWalkInfo);
                }
              }
            }
          }
        }
      } # GroupBy.Walk

      Context 'MarkdownPoShLogGenerator.Generate' {
        Context 'given: full history (no tags defined)' {
          It 'should: generate content' {
            InModuleScope Elizium.Klassy {
              [PoShLog]$changeLog, [PSCustomObject]$dependencies = Get-TestChangeLog -Options $_options;
              $changeLog.Init();

              [array]$releases = $changeLog.composePartitions();
              [object]$template = $_options.Output.Template;
              [string]$content = $dependencies.Generator.Generate(
                $releases, $template, $changeLog.TagsInRangeWithHead
              );
              $content | Should -Not -BeNullOrEmpty;
            }
            # rel, template
          }

          Context 'and: no GroupBy' {
            It 'should: generate content' {
              InModuleScope Elizium.Klassy {
                $_options.Selection.Tags = @{
                  PSTypeName = 'Klassy.PoShLog.Options.Selection.Tags';
                  Until      = '1.0.1';
                }
                $_options.Output.GroupBy = [string]::Empty;
                $_options.Output.Headings.H3 = '*{ungroupedStmt}';

                [PoShLog]$changeLog, [PSCustomObject]$dependencies = Get-TestChangeLog -Options $_options;
                $changeLog.Init();

                [array]$releases = $changeLog.composePartitions();
                [object]$template = $_options.Output.Template;
                [string]$content = $dependencies.Generator.Generate(
                  $releases, $template, $changeLog.TagsInRangeWithHead
                );
                $content | Should -Not -BeNullOrEmpty;
              }
            }
          } # and: no GroupBy
        } # given: full history (no tags defined)
      } # MarkdownPoShLogGenerator.Generate

      Context 'given: MarkdownPoShLogGenerator.CreateComparisonLinks' {
        It 'should: generate content' {
          InModuleScope Elizium.Klassy {
            [PoShLog]$changeLog, [PSCustomObject]$dependencies = Get-TestChangeLog -Options $_options;
            $changeLog.Init();

            [string]$content = $dependencies.Generator.CreateComparisonLinks(
              $changeLog.TagsInRangeWithHead
            );
            $content | Should -Not -BeNullOrEmpty;
          }
        }
      }

      Context 'given: MarkdownPoShLogGenerator.CreateDisabledWarnings' {
        It 'should: generate content' {
          InModuleScope Elizium.Klassy {
            [PoShLog]$changeLog, [PSCustomObject]$dependencies = Get-TestChangeLog -Options $_options;
            $changeLog.Init();

            [string]$content = $dependencies.Generator.CreateDisabledWarnings();
            $content | Should -Not -BeNullOrEmpty;
          }
        }
      }
    }
  } # composePartitions

  Describe 'given: PoShLog with Git' {
    Context 'and: klassy' {
      It 'should: Build real change log' {
        InModuleScope Elizium.Klassy {
          [PoShLog]$changeLog = New-PoShLog -Options $_options;
          $_changeLog.Init();

          [string]$content = $changeLog.Build();
          $content | Should -Not -BeNullOrEmpty;

          [string]$outputFile = 'ChangeLog-test.md';
          [string]$outputPath = Join-Path -Path $TestDrive -ChildPath $outputFile;
          $changeLog.Save($content, $outputPath);

          Test-Path -LiteralPath $outputPath | Should -BeTrue;
        }
      }
    }
  } # given: PoShLog with Git

  Describe 'GeneratorUtils' {
    Context 'Evaluate' {
      BeforeEach {
        InModuleScope Elizium.Klassy {
          [string]$script:_avatarLink = "<img title='plastikfan' src='https://github.com/plastikfan.png?size=24'>";
          [string]$script:_subject = 'feat(pstools)!: #145 Allow command to be invoked ...';
          [hashtable]$selectors = @{
            'scope'  = 'pstools';
            'type'   = 'feat';
            'change' = 'add';
          }
          [regex]$includeRegex = [regex]::new($_includes[1]);
          [System.Text.RegularExpressions.GroupCollection]$groups = `
            $includeRegex.Matches($_subject)[0].Groups;

          [PSCustomObject]$script:_commit = [PSCustomObject]@{
            PSTypeName = 'Klassy.PoShLog.CommitInfo';
            #
            Date       = [DateTime]::Parse('2021-04-19 16:17:04 +0100');
            CommitId   = 'dc800c6';
            FullHash   = 'dc800c68e4aaa6be692c8254490945ad73f69e6d';
            Author     = 'plastikfan';
            Subject    = $_subject;
            Info       = [PSCustomObject]@{ # => this replicates 'GroupByImpl.Partition'
              PSTypeName = 'Klassy.PoShLog.CommitInfo';
              Selectors  = $selectors;
              IsBreaking = $groups.ContainsKey('break') -and $groups['break'].Success;
              Groups     = $groups;
            }
            IsSquashed = $true;
          }

          [hashtable]$script:_variables = @{
            'author'        = $_commit.Author;
            'avatar-img'    = "<img title='plastikfan' src='https://github.com/plastikfan.png?size=24'>";
            'commitid'      = 'dc800c6';
            'commitid-link' = $("[dc800c6](https://github.com/EliziumNet/Loopz/" +
              "commit/dc800c68e4aaa6be692c8254490945ad73f69e6d)");
            'is-breaking'   = $_commit.Info.IsBreaking;
            'is-squashed'   = $true;
            'issue-link'    = "[#145](https://github.com/EliziumNet/Loopz/issues/145)";
            'subject'       = $_subject;
            'scope'         = 'pstools';
            'type'          = 'feat';
          }
        }
      }

      Context 'given: commit' {
        Context 'and: Statement <statement>' {
          It 'should: fully resolve to be "<expected>"' -TestCases @(
            @{
              Statement = 'AUTHOR:*{authorStmt}';
              Expected  = $(
                "AUTHOR: by ``@plastikfan`` :bird:"
              )
            },

            @{
              Statement = 'AVATAR:*{avatarStmt}';
              Expected  = $(
                "AVATAR: by ``@plastikfan`` " +
                "<img title='plastikfan' src='https://github.com/plastikfan.png?size=24'>"
              )
            },

            @{
              Statement = '?{is-breaking;breakStmt}';
              Expected  = ':warning: *BREAKING CHANGE* ';
            }

            @{
              Statement = '[Change Type: &{_C}+{change}] => ';
              Expected  = '[Change Type: :lock:] => ';
            },

            @{
              Statement = '?{change;changeStmt}';
              Expected  = [string]::Empty
            },

            @{
              Statement = '+ ?{break;breakStmt}*{changeStmt}*{subjectStmt}*{avatarStmt}';
              Expected  = $(
                "+ " +
                ":warning: *BREAKING CHANGE* " +
                "[Change Type: :lock:] => " +
                "Subject: **feat(pstools)!: #145 Allow command to be invoked ...**" +
                " by ``@plastikfan`` " +
                "<img title='plastikfan' src='https://github.com/plastikfan.png?size=24'>"
              );
            },

            @{
              Statement = '+ ?{break;breakStmt}?{change;changeStmt}*{subjectStmt}*{avatarStmt}';
              Expected  = $(
                "+ " +
                ":warning: *BREAKING CHANGE* " +
                "Subject: **feat(pstools)!: #145 Allow command to be invoked ...**" +
                " by ``@plastikfan`` " +
                "<img title='plastikfan' src='https://github.com/plastikfan.png?size=24'>"
              );
            },

            @{
              Statement = '!{dirty}';
              Expected  = ':poop:';
            },

            @{
              Statement = 'Scope(&{_S} +{scope})';
              Expected  = 'Scope(:parking: pstools)';
            },

            @{
              Statement = 'SQUASHED: *{subjectStmt}';
              Expected  = $(
                'SQUASHED: Subject: **feat(pstools)!: #145 Allow command to be invoked ...**'
              )
            },

            @{
              Statement = '?{is-squashed;squashedStmt}';
              Expected  = 'SQUASHED: ';
            },

            @{
              Statement = 'Subject: **+{subject}**';
              Expected  = 'Subject: **feat(pstools)!: #145 Allow command to be invoked ...**';
            },

            @{
              Statement = 'Commit-Type(&{_T} +{type})';
              Expected  = 'Commit-Type(:gift: feat)';
            },

            @{
              Statement = 'BODY: ^{body}';
              Expected  = 'BODY: Allow command to be invoked ...';
            },

            @{
              Statement = 'META INFO:*{metaStmt}';
              Expected  = $(
                'META INFO: (Id: [dc800c6](https://github.com/EliziumNet/Loopz/commit/dc800c68e4aaa6be692c8254490945ad73f69e6d))' +
                ' \<[#145](https://github.com/EliziumNet/Loopz/issues/145)\>'
              );
            },

            @{
              Statement = '*{metaStmt}';
              Expected  = $(
                ' (Id: [dc800c6](https://github.com/EliziumNet/Loopz/commit/dc800c68e4aaa6be692c8254490945ad73f69e6d))' +
                ' \<[#145](https://github.com/EliziumNet/Loopz/issues/145)\>'
              );
            },

            @{
              Statement = '?{issue-link;issueLinkStmt}';
              Expected  = $(
                ' \<[#145](https://github.com/EliziumNet/Loopz/issues/145)\>'
              );
            },

            @{
              Statement = '?{no-such-variable;issueLinkStmt}';
              Expected  = [string]::Empty;
            }
          ) {
            InModuleScope Elizium.Klassy -Parameters @{ Statement = $statement; Expected = $expected } {
              [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
              Param(
                [string]$statement,
                [string]$expected
              )
              [PoShLog]$changeLog, [PSCustomObject]$dependencies = Get-TestChangeLog -Options $_options;
              $changeLog.Init();

              $_variables['avatar-img'] = $dependencies.Generator._utils.AvatarImg($_commit.Author);

              [string]$result = $dependencies.Generator._utils.Evaluate(
                $Statement, $_commit, $_variables
              );
              [boolean]$assertion = $result.StartsWith($expected);
              if (-not($assertion)) {
                Write-Host $("FAILED: Statement: '$($Statement)'");
                Write-Host $("+ EXPECT: '$($expected)'");
                Write-Host $("+ ACTUAL: '$($result)'");
              }
              $assertion | Should -BeTrue;

              # Make sure every statement evaluated can run ok without a commit object
              # as is the case when a heading invokes Evaluate.
              #
              [void]$dependencies.Generator._utils.Evaluate(
                $Statement, $null, $_variables
              );
            }
          }
        }
      } # given: commit

      Context 'given: config error' {
        Context 'and: Statement <statement>' {
          It 'should: should throw "<because>"' -TestCases @(
            @{
              Statement = '*{blooperStmt}';
              Because   = "'blooperStmt' is not a defined statement";
            },

            @{
              Statement = '?{is-breaking;blooperStmt}';
              Because   = "'blooperStmt' is not a defined conditional statement";
            },

            @{
              Statement = '!{blooper}';
              Because   = "'blooper' is not a defined literal";
            },

            @{
              Statement = '[Change Type: &{_X}+{change}] => ';
              Because   = "'_X' is not a defined lookup";
            }
          ) {
            InModuleScope Elizium.Klassy -Parameters @{ Statement = $statement; Because = $because } {
              Param(
                [string]$statement,
                [string]$because
              )
              [PSCustomObject]$changeLog, [PSCustomObject]$dependencies = Get-TestChangeLog -Options $_options;
              $changeLog.Init();

              $_variables['avatar-img'] = $dependencies.Generator._utils.AvatarImg($_commit.Author);

              {
                $dependencies.Generator._utils.Evaluate(
                  $Statement, $_commit, $_variables
                );
              } | Should -Throw -Because $because;
            }
          }
        }

        Context 'and: recursive Statement' {
          It 'should: throw' {
            InModuleScope Elizium.Klassy {
              $_options.Output.Statements = [PSCustomObject]@{
                PSTypeName = 'Klassy.PoShLog.Options.Output.Statements';
                #
                Break      = '*{breakStmt} *BREAKING CHANGE* ';
              }
              [string]$statement = $_options.Output.Statements.Break;
              [PSCustomObject]$changeLog, [PSCustomObject]$dependencies = Get-TestChangeLog -Options $_options;
              $changeLog.Init();

              {
                $dependencies.Generator._utils.Evaluate(
                  $statement, $_commit, $_variables
                );
              } | Should -Throw;
            }
          }
        }

        Context 'and: recursive Conditional Statement' {
          It 'should: throw' {
            InModuleScope Elizium.Klassy {
              $_options.Output.Statements = [PSCustomObject]@{
                PSTypeName = 'Klassy.PoShLog.Options.Output.Statements';
                #
                Break      = '?{is-breaking;breakStmt} *BREAKING CHANGE* ';
              }
              [string]$statement = $_options.Output.Statements.Break;
              [PSCustomObject]$changeLog, [PSCustomObject]$dependencies = Get-TestChangeLog -Options $_options;
              $changeLog.Init();

              {
                $dependencies.Generator._utils.Evaluate(
                  $statement, $_commit, $_variables
                );
              } | Should -Throw;
            }
          }
        }
      } # given: config error
    } # Evaluate

    Context 'CreateIsaLookup' -Tag 'Current' {
      Context 'given: simple parent' {
        It 'should: return remapped value' {
          [hashtable]$optionTypes = @{
            "Performance" = ":hammer:";
            "perf"        = "isa:Performance";
          }
          [PSCustomObject]$types = [GeneratorUtils]::CreateIsaLookup(
            'Types', $optionTypes
          );
          [string]$type = 'perf';

          $types.Isa[$type] | Should -BeExactly 'Performance';
          $types.Value[$type] | Should -BeExactly ':hammer:'; 
        }
      }

      Context 'given: parent with spaces' {
        It 'should: return remapped value' {
          [hashtable]$optionScopes = @{
            "Parameter Set Tools" = ":postbox:";
            "pstools"             = "isa:Parameter Set Tools";
          }
          [PSCustomObject]$scopes = [GeneratorUtils]::CreateIsaLookup(
            'Scopes', $optionScopes
          );
          [string]$scope = 'pstools';

          $scopes.Isa[$scope] | Should -BeExactly 'Parameter Set Tools';
          $scopes.Value[$scope] | Should -BeExactly ':postbox:';
        }
      }

      Context 'given: entry refers to itself' {
        It 'should: throw' {
          {
            [GeneratorUtils]::CreateIsaLookup('Scopes', @{
                "Parameter Set Tools" = ":postbox:";
                "pstools"             = "isa:pstools";
              });
          } | Should -Throw;
        }
      }

      Context 'given: entry refers to non existent parent' {
        It 'should: throw' {
          {
            [GeneratorUtils]::CreateIsaLookup('Scopes', @{
                "Parameter Set Tools" = ":postbox:";
                "pstools"             = "isa:blooper";
              });
          } | Should -Throw;
        }
      }
    }
  } # GeneratorUtils

  Describe 'PoShLogOptionsManager' {
    Context 'given: requested <name> options does exist' {
      It 'should: create new options' -TestCases @(
        @{ Name = 'Alpha' },
        @{ Name = 'Elizium' },
        @{ Name = 'Zen' },
        @{ Name = 'Unicorn' }
      ) {
        InModuleScope Elizium.Klassy -Parameters @{ Name = $name; } {
          param(
            [string]$Name
          )
          [string]$root = 'root';
          [string]$rootPath = Join-Path -Path $TestDrive -ChildPath $root;
          [PSCustomObject]$optionsInfo = [PSCustomObject]@{
            Base          = '-changelog.options';
            DirectoryName = [PoShLogProfile]::DIRECTORY;
            GroupBy       = 'scope/type/change/break';
            Root          = $rootPath;
          }

          [PoShLogOptionsManager]$manager = New-PoShLogOptionsManager -OptionsInfo $optionsInfo;
          [boolean]$withEmoji = $true;

          [PSCustomObject]$options = $manager.FindOptions($Name, $withEmoji);
          $manager.Found | Should -BeFalse;
          $options | Should -Not -BeNullOrEmpty;

          [PoShLog]$changeLog = New-PoShLog -Options $options;
          $changeLog.Build() | Should -Not -BeNullOrEmpty;
        }
      }
    }

    Context 'given: requested options exist' {
      It 'should: load existing options and build' {
        InModuleScope Elizium.Klassy {
          [string]$directoryName = [PoShLogProfile]::DIRECTORY;
          [string]$root = 'root';
          [string]$rootPath = Join-Path -Path $TestDrive -ChildPath $root;
          [PSCustomObject]$optionsInfo = [PSCustomObject]@{
            Base          = '-changelog.options';
            DirectoryName = $directoryName;
            GroupBy       = 'scope/type/change/break';
            Root          = $rootPath;
          }
          [string]$directoryPath = Join-Path -Path $rootPath -ChildPath $directoryName;
          [string]$optionsFileName = 'Test-emoji-changelog.options.json';
          [string]$testPath = "./Tests/Data/changelog/$optionsFileName";

          [void]$(New-Item -ItemType 'Directory' -Path $directoryPath);
          [string]$destinationPath = Join-Path -Path $directoryPath -ChildPath $optionsFileName;
          Copy-Item -LiteralPath $testPath -Destination $destinationPath;

          [PoShLogOptionsManager]$manager = New-PoShLogOptionsManager -OptionsInfo $optionsInfo;
          [boolean]$withEmoji = $true;

          [PSCustomObject]$options = $manager.FindOptions('Test', $withEmoji);
          $manager.Found | Should -BeTrue;
          $options | Should -Not -BeNullOrEmpty;

          [PoShLog]$changeLog = New-PoShLog -Options $options;
          $changeLog.Build() | Should -Not -BeNullOrEmpty; ;
        }
      }
    }

    Context 'given: json-schema' {
      It 'should: validate options ok' {
        InModuleScope Elizium.Klassy {
          [string]$optionsFileName = 'Test-emoji-changelog.options.json';
          [string]$testPath = "./Tests/Data/changelog/$($optionsFileName)";
          [string]$schemaFileName = [PoShLogProfile]::OPTIONS_SCHEMA_FILENAME;
          [string]$schemaPath = "./FileList/$($schemaFileName)";
          [string]$json = Get-Content -LiteralPath $testPath;
          $null = Test-Json -Json $json -SchemaFile $schemaPath;
        }
      }
    }
  } # PoShLogOptionsManager
} # PoShLog
