
# === [ SourceControl ] ========================================================
#
class SourceControl {
  [PSCustomObject]$Options;
  hidden [PSCustomObject[]]$_allTagsWithHead;
  hidden [PSCustomObject[]]$_allTagsWithoutHead;
  hidden [DateTime]$_headDate; # date of last commit
  hidden [DateTime]$_lastReleaseDate; # date of last release (can be null if no releases)
  static [int]$DEFAULT_COMMIT_ID_SIZE = 7;
  [int]$_commitIdSize;

  SourceControl([PSCustomObject]$options) {
    $this.Options = $options;
  }

  [void] Init([boolean]$descending) {
    [boolean]$includeHead = $true;
    $this._allTagsWithHead = $this.ReadSortedTags($includeHead, $descending);

    $includeHead = $false;
    $this._allTagsWithoutHead = $this.ReadSortedTags($includeHead, $descending);

    $this._commitIdSize = try {
      [int]$size = [int]::Parse($this.Options.SourceControl.CommitIdSize);
      
      $($size -in 7..40) ? $size : [SourceControl]::DEFAULT_COMMIT_ID_SIZE;
    }
    catch {
      [SourceControl]::DEFAULT_COMMIT_ID_SIZE;
    }
  }

  [PSCustomObject[]] GetSortedTags([boolean]$includeHead) {
    return $includeHead ? $this._allTagsWithHead : $this._allTagsWithoutHead;
  }

  [PSCustomObject[]] ReadGitTags([boolean]$includeHead) {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (SourceControl.ReadGitTags)');
  }

  [string] ReadRemoteUrl() {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (SourceControl.ReadRemoteUrl)');
  }

  [string] ReadRootPath() {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (SourceControl.ReadRootPath)');
  }

  [PSCustomObject[]] ReadSortedTags([boolean]$includeHead, [boolean]$descending) {

    [PSCustomObject[]]$unsorted = $this.ReadGitTags($includeHead);
    [PSCustomObject[]]$sorted = $unsorted | Sort-Object -Property 'Date' -Descending:$descending;

    return $sorted;
  }

  [PSCustomObject[]] ReadGitCommitsInRange(
    [string]$Format,
    [string]$Range,
    [string[]]$Header,
    [string]$Delim
  ) {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (SourceControl.ReadGitCommitsInRange)');
  }

  [DateTime] GetTagDate ([string]$Label) {
    [PSCustomObject]$foundTagInfo = $this.GetSortedTags($true) | `
      Where-Object { $_.Label -eq $Label }

    if (-not($foundTagInfo)) {
      throw [System.Management.Automation.MethodInvocationException]::new(
        "SourceControl.GetTagDate: Tag: '$Label' not found");
    }

    return $foundTagInfo.Date;
  }

  [DateTime] GetLastReleaseDate() {
    [PSCustomObject[]]$sortedTags = $this.GetSortedTags($false);

    [DateTime]$releaseDate = if ($sortedTags.Count -gt 0) {
      $sortedTags[0].Date;
    }
    else {
      $null;
    }

    return $releaseDate;
  }

  [string[]] GetTagRange([regex]$RangeRegex, [string]$Range) {
    [System.Text.RegularExpressions.MatchCollection]$mc = $RangeRegex.Matches($Range);

    if (-not($rangeRegex.IsMatch($Range))) {
      throw "bad range: '$Range'";
    }
    [System.Text.RegularExpressions.Match]$m = $mc[0];
    [System.Text.RegularExpressions.GroupCollection]$groups = $m.Groups;

    [string]$from = $groups['from'];
    [string]$until = $groups['until'];

    return $from, $until;
  }

  # Returns: [PSTypeName('Loopz.ChangeLog.TagInfo')][array]
  #
  [PSCustomObject[]] processTags ([PSCustomObject[]]$gitTags, [boolean]$includeHead) {
    [regex]$tagRegex = "(?<dt>[^\(]+)\(tag: (?<tag>[^\)]+)\)";
    [regex]$versionRegex = [regex]::new("(?<ver>\d\.\d\.\d)");

    [array]$result = foreach ($prettyTag in $gitTags) {
      if ($tagRegex.IsMatch($prettyTag)) {
        [System.Text.RegularExpressions.MatchCollection]$mc = $tagRegex.Matches($prettyTag);
        [System.Text.RegularExpressions.Match]$m = $mc[0];
        [System.Text.RegularExpressions.GroupCollection]$groups = $m.Groups;

        [string]$dt = $groups['dt'].Value.Trim();
        [string]$tag = $groups['tag'].Value;
        [DateTime]$date = [DateTime]::Parse($dt)

        [PSCustomObject]$tagInfo = [PSCustomObject]@{
          PSTypeName = 'Loopz.ChangeLog.TagInfo';
          Label      = $tag;
          Date       = $date;
        }

        if ($versionRegex.IsMatch($tag)) {
          [System.Text.RegularExpressions.MatchCollection]$mc = $versionRegex.Matches($tag);
          [string]$version = $mc[0].Value;
          $tagInfo | Add-Member -NotePropertyName 'Version' -NotePropertyValue $version;
        }

        $tagInfo;
      }
      else {
        throw [System.Management.Automation.MethodInvocationException]::new(
          "processTags: Bad tag found: '$($prettyTag)'");
      }
    }

    if ($includeHead -and $this._headDate) {
      $result = $result += [PSCustomObject]@{
        PSTypeName = 'Loopz.ChangeLog.TagInfo';
        Label      = 'HEAD';
        Date       = $this._headDate;
      }
    }

    return $result;
  } # processTags
} # SourceControl

# === [ Git ] ==================================================================
#
class Git : SourceControl {
  # Ideally, _gitCi should be used to execute all git commands. However, doing so and 
  # passing in the parameters is tricky, which is the reason why git is invoked directly,
  # until the correct way to invoke with arguments has been determined.
  # The invoke options are:
  # - Call Op: & "path/blah.exe" "param1" "param2"
  # - Invoke-Command
  # - Invoke-Expression
  # - Invoke-Item
  #
  # See also:
  # https://social.technet.microsoft.com/wiki/contents/articles/7703.powershell-running-executables.aspx
  #
  hidden [System.Management.Automation.CommandInfo]$_gitCi;

  Git([PSCustomObject]$options): base($options) {
    # Just check that git is available
    # TODO: check the digital signature
    # https://mcpmag.com/articles/2018/07/25/file-signatures-using-powershell.aspx
    #
    $this._gitCi = Get-Command 'git' -ErrorAction Stop;
    if (-not($this._gitCi -and ($this._gitCi.CommandType -eq
          [System.Management.Automation.CommandTypes]::Application))) {

      throw [System.Management.Automation.MethodInvocationException]::new(
        'git not found');
    }

    # %ai = author date, ISO 8601-like format
    # eg: '2021-04-19 18:20:49 +0100'
    #
    [string]$head = $(git log -n 1 --format=%ai);
    $this._headDate = [DateTime]::Parse($head);
  } # ctor.Git

  [PSCustomObject[]] ReadGitTags([boolean]$includeHead) {
    # The 'i' in '%ci' wraps the date inside brackets and this is reflected in the regex pattern
    # %d: ref names
    # eg: '2021-04-19 18:17:15 +0100  (tag: 3.0.2)'
    #
    [array]$tags = (git log --tags --simplify-by-decoration --pretty="format:%ci %d") -match 'tag:';
    return $this.processTags($tags, $includeHead);
  } # ReadGitTags

  # Returns: [PSTypeName('Loopz.ChangeLog.CommitInfo')][]
  #
  [PSCustomObject[]] ReadGitCommitsInRange(
    [string]$Format,
    [string]$Range,
    [string[]]$Header,
    [string]$Delim
  ) {
    Write-Debug "ReadGitCommitsInRange: RANGE: '$($Range)', FORMAT: '$($Format)'.";

    $commitContent = (git log $Range --format=$Format);
    [array]$result = $commitContent | ConvertFrom-Csv -Delimiter $Delim -Header $Header;

    $result | Where-Object { $null -ne $_.CommitId } | ForEach-Object {
      Add-Member -InputObject $_ -PassThru -NotePropertyMembers @{
        PSTypeName = 'Loopz.ChangeLog.CommitInfo';
        FullHash   = $_.CommitId;
      }
    } | ForEach-Object {
      $_.CommitId = $_.CommitId.SubString(0, $this._commitIdSize);
      $_.Date = [DateTime]::Parse($_.Date); # convert date
    }

    return $result;
  } # ReadGitCommitsInRange

  [string] ReadRemoteUrl() {
    return (git remote get-url origin) -replace '\.git$';
  }

  [string] ReadRootPath() {
    return $(git rev-parse --show-toplevel);
  }
} # Git

# === [ ChangeLog ] ============================================================
#
class ChangeLog {
  [PSCustomObject]$Options;
  [SourceControl]$SourceControl;
  [boolean]$IsDescending;
  hidden [regex]$_squashRegex;
  hidden [GroupBy]$_grouper;
  hidden [ChangeLogGenerator]$_generator;

  ChangeLog([PSCustomObject]$options,
    [SourceControl]$sourceControl,
    [GroupBy]$grouper,
    [ChangeLogGenerator]$generator) {

    $this.Options = $options;
    $this.SourceControl = $sourceControl;
    $this._grouper = $grouper;
    $this._generator = $generator;

    $this.IsDescending = -not(($this.Options.Selection)?.Order -and
      (($this.Options.Selection)?.Order -eq 'asc'));
    $this._grouper.SetDescending($this.IsDescending);
    $this._generator.SetDescending($this.IsDescending);

    $this._squashRegex = if (($this.Options.Selection)?.SquashBy `
        -and -not([string]::IsNullOrEmpty($this.Options.Selection.SquashBy))) {
      [regex]::new($this.Options.Selection.SquashBy);
    }
    else {
      $null;
    }

    $sourceControl.Init($this.IsDescending);
  } # ctor.ChangeLog

  [string] Build() {
    [array]$releases = $this.composePartitions();
    [string]$template = $this.Options.Output.Template;
    [string]$content = $this._generator.Generate($releases, $template);

    return $content;
  }

  # Return: [PSTypeName('Loopz.ChangeLog.PartitionedRelease')][array]
  #
  [PSCustomObject[]] composePartitions() {

    [hashtable]$releases = $this.processCommits();
    [PSCustomObject[]]$allTags = $this.SourceControl.GetSortedTags($true);

    return $this._grouper.Partition($releases, $allTags);
  }

  # Returns: ('Loopz.ChangeLog.CommitInfo')[]
  #
  [PSCustomObject[]] GetTagsInRange([boolean]$includeHead) {
    [PSCustomObject[]]$allTags = $this.SourceControl.GetSortedTags($includeHead);

    [scriptblock]$whereTagsInRange = if (($this.Options.Tags)?.From -and ($this.Options.Tags)?.Until) {
      [scriptblock] {
        [string]$from = ($this.Options.Tags)?.From;
        [string]$until = ($this.Options.Tags)?.Until;

        [DateTime]$fromDate = $this.SourceControl.GetTagDate($from);
        [DateTime]$untilDate = $this.SourceControl.GetTagDate($until);

        $this.IsDescending ? $_.Date -ge $fromDate -and $_.Date -le $untilDate `
          : $_.Date -le $fromDate -and $_.Date -ge $untilDate;
      }
    }
    elseif (($this.Options.Tags)?.From) {
      [scriptblock] {
        [string]$from = ($this.Options.Tags)?.From;
        [DateTime]$fromDate = $this.SourceControl.GetTagDate($from);

        $this.IsDescending ? $_.Date -ge $fromDate : $_.Date -le $fromDate;
      }
    }
    elseif (($this.Options.Tags)?.Until) {
      [scriptblock] {
        [string]$until = ($this.Options.Tags)?.Until;
        [DateTime]$untilDate = $this.SourceControl.GetTagDate($until);

        $this.IsDescending ? $_.Date -le $untilDate : $_.Date -ge $untilDate;
      }
    }
    elseif (($this.Options.Tags)?.Unreleased) {
      [scriptblock] {
        [DateTime]$lastDate = $this.SourceControl.GetLastReleaseDate();

        if ($lastDate) {
          $this.IsDescending ? $_.Date -ge $lastDate : $_.Date -le $lastDate;
        }
        else {
          # There are no releases but there are commits, we should still be able
          # to build a change log
          #
          $true;
        }
      }      
    }
    else {
      [scriptblock] { $true } # => Select all tags by default
    }
    [PSCustomObject[]]$result = ($allTags | Where-Object $whereTagsInRange);

    return $result;
  } # GetTagsInRange

  # Returned releases are a hashtable keyed by tag label => [PSTypeName('Loopz.ChangeLog.SquashedRelease')]
  #
  [hashtable] processCommits() {
    [PSCustomObject[]]$tags = $this.GetTagsInRange($false);

    # NB: WARNING, do not select the body; if it is multiline, then it will break
    # all of this, because the assumption is that 1 commit = 1 line of content
    #
    [string]$format = "%ai`t%H`t%an`t%s";
    [string[]]$header = @("Date", "CommitId", "Author", "Subject");
    [string]$delim = "`t";

    [boolean]$untilMissing = -not(($this.Options.Tags)?.Until);
    [string]$until = if (($this.Options.Tags)?.Unreleased -or ($untilMissing)) {
      'HEAD';
    }
    elseif (-not($untilMissing)) {
      ($this.Options.Tags)?.Until;
    }

    [hashtable]$releases = [ordered]@{}
    
    Write-Debug "========= [ processCommits: tags ($($tags.Count)): '$($tags.Label -join ', ')' ] ====";

    foreach ($tagInfo in $tags) {
      [string]$from = $tagInfo.Label;
      [string]$range = "$from..$until";

      if ($from -ne $until) {
        # Attach an auxiliary Info field for later use
        #
        [array]$inRange = $this.SourceControl.ReadGitCommitsInRange(
          $format, $range, $header, $delim
        ) | ForEach-Object {
          Add-Member -InputObject $_ -NotePropertyName 'Info' -NotePropertyValue $null -PassThru;
        };

        foreach ($com in $inRange) {
          [string]$displayDate = $com.Date.ToString('yyyy-MM-dd - HH:mm:ss');
          Write-Debug "    ---> FROM: '$from', UNTIL: '$until' PRE-FILTERED COUNT: '$($inRange.Count)' <---";
          Write-Debug "      + '$($com.Subject)', DATE: '$($displayDate)'";
          Write-Debug "    --------------------------";
          Write-Debug "";
        }

        [PSCustomObject]$squashed = $this.filterAndSquashCommits($inRange, $until);

        if ($squashed) {
          $releases[$until] = $squashed;
        }
      }
      else {
        Write-Debug "    ---> SKIPPING: FROM: '$from', UNTIL: '$until' <---";
      }

      $until = $from; 
    }

    return $releases;
  } # processCommits

  # Filter and squash commits for a single release denoted by the Until label.
  # Returns a PSCustomObject instance with members:
  # - Squashed: hash indexed by issue no
  # - Commits: array of commits (no issue number, or squash not enabled)
  # - Label: until tag label for the release
  # - Dirty: array of unfiltered commits; release contains commits all filtered out.
  #
  # Returns: [PSTypeName('Loopz.ChangeLog.SquashedRelease')]
  #
  [PSCustomObject] filterAndSquashCommits([array]$commitsInRange, [string]$untilLabel) {
    [array]$filtered = $this.filter($commitsInRange, $untilLabel);
    [PSCustomObject]$result = if ($this._squashRegex) {

      [System.Collections.Generic.List[PSCustomObject]]$commitsWithoutIssueNo = `
        [System.Collections.Generic.List[PSCustomObject]]::new();

      [hashtable]$squashedHash = [ordered]@{}

      foreach ($commit in $filtered) {
        [System.Text.RegularExpressions.MatchCollection]$mc = $this._squashRegex.Matches(
          $commit.Subject
        );

        if ($mc.Count -gt 0) {
          [string]$issue = $mc[0].Groups['issue'];

          if ($squashedHash.ContainsKey($issue)) {
            $squashedItem = $squashedHash[$issue];
            $commit | Add-Member -NotePropertyName 'IsSquashed' -NotePropertyValue $true;

            # Do squash
            #
            if ($squashedItem -is [System.Collections.Generic.List[PSCustomObject]]) {
              $squashedItem.Add($commit); # => 3rd or more commit with this issue no
            }
            else {
              [System.Collections.Generic.List[PSCustomObject]]$newSquashedGroup = `
                [System.Collections.Generic.List[PSCustomObject]]::new();
              $squashedItem | Add-Member -NotePropertyName 'IsSquashed' -NotePropertyValue $true;
              $newSquashedGroup.Add($squashedItem); # => pre-existing first
              $newSquashedGroup.Add($commit); # => second commit
              $squashedHash[$issue] = $newSquashedGroup;
            }
          }
          else {
            $squashedHash[$issue] = $commit; # => first commit with this issue no
          }
        }
        else {
          if (($this.Options.Selection)?.IncludeMissingIssue -and
            $this.Options.Selection.IncludeMissingIssue) {
            $commitsWithoutIssueNo.Add($commit);
          }
        }
      }
      [PSCustomObject]$release = [PSCustomObject]@{
        PSTypeName = 'Loopz.ChangeLog.SquashedRelease';
        Squashed   = $squashedHash;
        Commits    = $commitsWithoutIssueNo;
        Label      = $untilLabel;
      }
      $release;
    }
    else {
      [PSCustomObject]$release = [PSCustomObject]@{
        PSTypeName = 'Loopz.ChangeLog.SquashedRelease';
        Commits    = $filtered;
        Label      = $untilLabel;
      }
      $release;
    }

    [boolean]$noSquashed = -not($result.Squashed) `
      -or ($result.Squashed -and ($result.Squashed.PSBase.Count -eq 0));

    [boolean]$noCommits = -not($result.Commits) `
      -or ($result.Commits -and ($result.Commits.Count -eq 0));

    if ($noSquashed -and $noCommits) {
      # No commits for release
      #
      $result = @{
        Dirty = $commitsInRange;
        Label = $untilLabel;
      };
    }

    return $result;
  } # filterAndSquashCommits

  [array] filter([array]$commits, [string]$untilLabel) {

    [regex[]]$includes = $this._grouper.BuildIncludes();
    [regex[]]$excludes = $this._grouper.BuildExcludes();

    [array]$filtered = $commits;

    if (($this.Options.Selection.Subject)?.Include) {
      $filtered = ($filtered | Where-Object {
          $this._grouper.TestMatchesAny($_.Subject, $includes);
        });    
    }

    if ($filtered) {
      $filtered = ($filtered | Where-Object {
          -not($this._grouper.TestMatchesAny($_.Subject, $excludes));
        });
    }

    if (-not($filtered)) {
      $filtered = @();
      Write-Debug "!!! Release: '$untilLabel'; no commits";
    }
    return $filtered;
  } # filter
} # ChangeLog

# === [ GroupBy ] ==============================================================
#

class GroupBy {
  [void] SetDescending([boolean]$value) {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (GroupBy.BuildExcludes)');
  }

  [boolean] TestMatchesAny([string]$subject, [regex[]]$expressions) {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (GroupBy.TestMatchesAny)');
  } # TestMatchesAny

  [regex[]] BuildExpressions([string[]]$expressions) {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (GroupBy.BuildExpressions)');
  } # BuildExpressions

  [regex[]] BuildIncludes() {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (GroupBy.BuildIncludes)');
  } # BuildIncludes

  [regex[]] BuildExcludes() {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (GroupBy.BuildExcludes)');
  } # BuildExcludes

  [PSCustomObject[]] Partition(
    [hashtable]$releases, [string[]]$expressions, [PSCustomObject[]]$sortedTags) {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (GroupBy.Partition)');
  } # Partition

  [void] Walk([PSCustomObject]$partitionedRelease, [PSCustomObject]$handlers, [PSCustomObject]$custom) {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (GroupBy.Walk)');
  } # Walk
}

# === [ GroupByImpl ] ==========================================================
#
class GroupByImpl : GroupBy {
  [PSCustomObject]$Options;
  [boolean]$IsDescending = $true;
  hidden [string[]]$_segments;
  hidden [string]$_leafSegment;
  hidden [string]$_prefix = "partitions:";
  hidden [string]$_uncategorised = "uncategorised";
  hidden [string]$_dirty = "dirty";

  GroupByImpl([PSCustomObject]$options) {
    $this.Options = $options;
    $this._segments = -not([string]::IsNullOrEmpty($this.Options.Output.GroupBy)) ? `
      $this.Options.Output.GroupBy -split '/' : @();

    $this._leafSegment = ($this._segments.Count -gt 0) ? $this._segments[-1] : [string]::Empty;
  } # ctor

  [void] SetDescending([boolean]$value) {
    $this.IsDescending = $value;
  }

  [boolean] TestMatchesAny([string]$subject, [regex[]]$expressions) {
    return ($null -ne $this.GetMatchingRegex($subject, $expressions));
  } # TestMatchesAny

  [regex[]] BuildExpressions ([string[]]$expressions) {
    [regex[]]$result = foreach ($expr in $expressions) {
      [regex]::new($expr);
    }
    return $result;
  } # BuildExpressions

  [regex[]] BuildIncludes() {
    return $this.BuildExpressions(
      ($this.Options.Selection.Subject.Include -is [array]) ? `
        $this.Options.Selection.Subject.Include : @($this.Options.Selection.Subject.Include)
    );
  } # BuildIncludes

  [regex[]] BuildExcludes() {
    return $this.BuildExpressions(
      ($this.Options.Selection.Subject.Exclude -is [array]) ? `
        $this.Options.Selection.Subject.Exclude : @($this.Options.Selection.Subject.Exclude)
    );
  } # BuildExcludes

  [regex] GetMatchingRegex([string]$subject, [regex[]]$expressions) {
    [regex]$matched = $null;
    [int]$current = 0;

    while (-not($matched) -and ($current -lt $expressions.Count)) {
      [regex]$filterRegex = $expressions[$current];
      if ($filterRegex.IsMatch($subject)) {
        $matched = $filterRegex;
      }
      $current++;
    }

    return $matched;
  } # GetMatchingRegex

  # Resolves a path to a leaf. The leaf represents the bucket of commits resolved
  # to from the path.
  #
  # $segmentInfo: [PSTypeName('Loopz.ChangeLog.SegmentInfo')]
  # $partitionedRelease: [PSTypeName('Loopz.ChangeLog.PartitionedRelease')]
  # $handlers: [PSTypeName('Loopz.ChangeLog.Handler')]
  # $custom: [PSTypeName('Loopz.ChangeLog.WalkInfo')]
  #
  [PSCustomObject[]] resolve(
    [PSCustomObject]$segmentInfo,
    [PSCustomObject]$partitionedRelease,
    [PSCustomObject]$handlers,
    [PSCustomObject]$custom) {

    [PSCustomObject]$tagInfo = $partitionedRelease.Tag;
    [hashtable]$partitions = $partitionedRelease.Partitions;

    [PSCustomObject[]]$commits = if ($segmentInfo.Legs.Count -gt 0) {
      $pointer = $partitions;

      [int]$current = 0;
      foreach ($leg in $segmentInfo.Legs) {
        if ($current -eq 0) {
          # Invoke H3
          #
          $segmentInfo.ActiveSegment = $this._segments[$current];
          $segmentInfo.ActiveLeg = $leg;
          $handlers.OnHeading(
            'H3', $this.Options.Output.Headings.H3,
            $segmentInfo, $tagInfo, $handlers.Utils, $custom
          );
          $segmentInfo.ActiveSegment = [string]::Empty; # should be able to set this
          $segmentInfo.ActiveLeg = [string]::Empty; # should be able to set this
        }

        if ($current -eq 1) {
          # Invoke H4
          #
          $segmentInfo.ActiveSegment = $this._segments[$current];
          $segmentInfo.ActiveLeg = $leg;
          $handlers.OnHeading(
            'H4', $this.Options.Output.Headings.H4,
            $segmentInfo, $tagInfo, $handlers.Utils, $custom
          );
          $segmentInfo.ActiveSegment = [string]::Empty;
          $segmentInfo.ActiveLeg = [string]::Empty;
        }

        $pointer = $pointer[$leg];
        $current++;
      }

      if (-not($pointer -is [System.Collections.Generic.List[PSCustomObject]])) {
        throw [System.Management.Automation.MethodInvocationException]::new(
          "GroupByImpl.Resolve: failed to resolve path: '$($segmentInfo.Path)' to commits");
      }
      $pointer;
    }
    else {
      # Uncategorised commits go under a H3
      #
      $partitions[$this._uncategorised];
    }

    return $commits;
  } # resolve

  # Returns: [PSTypeName('Loopz.ChangeLog.SegmentInfo')]
  #
  [PSCustomObject] createSegmentInfo([string]$path) {
    [string[]]$legs = ($path -split '/') | Where-Object { $_ -ne $this._prefix; }

    [int]$legIndex = 0;
    [System.Collections.Generic.List[string]]$decoratedSegments = `
      [System.Collections.Generic.List[string]]::new();
    [hashtable]$segmentToLeg = @{}

    $legs | ForEach-Object {
      [string]$segment = $this._segments[$legIndex];
      $decoratedSegments.Add("$($segment):$_");
      $segmentToLeg[$segment] = $_;

      $legIndex++;
    }
    [string]$decoratedPath = $decoratedSegments -join '/';

    [PSCustomObject]$segmentInfo = [PSCustomObject]@{
      PSTypeName    = 'Loopz.ChangeLog.SegmentInfo';
      Path          = $path;
      Legs          = $legs;
      DecoratedPath = $decoratedPath;
      ActiveSegment = [string]::Empty;
      ActiveLeg     = [string]::Empty;
      IsDirty       = $false;
    }

    $this._segments | ForEach-Object {
      $segmentInfo | Add-Member -NotePropertyName $_ -NotePropertyValue $segmentToLeg[$_];
    }

    return $segmentInfo;
  } # createSegmentInfo

  # A partitioned release contains Partitions and Tag members
  #
  # $partitionedRelease: [PSTypeName('Loopz.ChangeLog.PartitionedRelease')]
  # $handlers: [PSTypeName('Loopz.ChangeLog.Handlers')]
  # $custom: [PSTypeName('Loopz.ChangeLog.WalkInfo')]
  #
  [void] Walk(
    [PSCustomObject]$partitionedRelease,
    [PSCustomObject]$handlers,
    [PSCustomObject]$custom) {

    [PSCustomObject]$tagInfo = $partitionedRelease.Tag;
    [hashtable]$partitions = $partitionedRelease.Partitions;
    [string[]]$paths = $partitionedRelease.Paths;
    [int]$cleanCount = 0;

    # named partitions first
    #
    foreach ($path in $paths) {
      [PSCustomObject]$segmentInfo = $this.createSegmentInfo($path);
      [PSCustomObject[]]$bucket = $this.resolve(
        $segmentInfo, $partitionedRelease, $handlers, $custom
      );

      foreach ($commit in $bucket) {
        # Sort the commits first?
        $handlers.OnCommit(
          $segmentInfo, $commit, $tagInfo, $handlers.Utils, $custom
        );
        $cleanCount++;
      }

      [PSCustomObject]$segmentInfo = [PSCustomObject]@{
        PSTypeName    = 'Loopz.ChangeLog.SegmentInfo';
        Path          = [string]::Empty;
        DecoratedPath = [string]::Empty;
      }
      $handlers.OnEndBucket($segmentInfo, $tagInfo, $handlers.Utils, $custom);
    }

    if (($cleanCount -eq 0) -and $partitions.ContainsKey($this._dirty)) {
      [PSCustomObject]$segmentInfo = [PSCustomObject]@{
        PSTypeName    = 'Loopz.ChangeLog.SegmentInfo';
        Path          = [string]::Empty;
        DecoratedPath = [string]::Empty;
        IsDirty       = $true;
      }
      $handlers.OnHeading(
        'Dirty', $this.Options.Output.Headings.Dirty,
        $segmentInfo, $tagInfo, $handlers.Utils, $custom
      );

      [PSCustomObject]$dirtyCommit = $partitions[$this._dirty][0];
      $handlers.OnCommit(
        $this._dirty, $dirtyCommit, $tagInfo, $handlers.Utils, $custom
      );

      $handlers.OnEndBucket(
        $segmentInfo, $tagInfo, $handlers.Utils, $custom
      );
    }
  } # Walk

  # To generate the output, we need the releases to be in descending order of
  # the date, but of course, we need to be able to identify each release. Building
  # a hash of release tag to the release collection will not guarantee the order
  # if it's in a hash. So, we need an array. Partition will return an array of
  # PSCustomObjects containing fields: Tag, Partitions and Paths.
  #
  # $sortedTags: [PSTypeName('Loopz.ChangeLog.TagInfo')]
  #
  # Returns: [PSTypeName('Loopz.ChangeLog.PartitionedRelease')][array]
  #
  [PSCustomObject[]] Partition([hashtable]$releases, [PSCustomObject[]]$sortedTags) {

    [regex[]]$expressions = $this.BuildIncludes();
    [System.Collections.Generic.List[PSCustomObject]]$partitioned = `
      [System.Collections.Generic.List[PSCustomObject]]::new();

    foreach ($tag in $sortedTags) {
      if ($releases.ContainsKey($tag.Label)) {
        [PSCustomObject]$release = $releases[$tag.Label];
        [PSCustomObject[]]$commits = $this.flatten($release);

        [hashtable]$partitions = @{}
        $pointer = $partitions;

        [System.Collections.Generic.List[string]]$paths = `
          [System.Collections.Generic.List[string]]::new();

        if ($this._segments.Count -eq 0) {
          $partitions[$this._uncategorised] = $commits;
        }
        else {
          Write-Debug "--->>> Partition for release '$($tag.Label)':";

          foreach ($com in $commits) {
            [regex]$partitionRegex = $this.GetMatchingRegex($com.Subject, $expressions);

            if (-not($partitionRegex)) {
              throw [System.Management.Automation.MethodInvocationException]::new(
                "GroupByImpl.Partition: (TAG: '$($tag.Label)') " +
                "internal logic error; commit: '$($com.Subject)' does not match");
            }

            [hashtable]$selectors = @{}
            [System.Text.RegularExpressions.MatchCollection]$mc = $partitionRegex.Matches($com.Subject);
            [System.Text.RegularExpressions.GroupCollection]$groups = $mc[0].Groups;

            'change', 'scope', 'type' | ForEach-Object {
              if ($groups.ContainsKey($_) ) {
                $selectors[$_] = $groups[$_];
              }
            }

            if (-not($groups.ContainsKey('change'))) {
              # TODO: try categorising the change by other means. This will be difficult
              # and depends on the quality of the commit messages. The user will have
              # to perform some manual re-arrangement of commits by change type in the
              # generated output.
              #
            }

            $com.Info = [PSCustomObject]@{
              PSTypeName = 'Loopz.ChangeLog.CommitInfo';
              Selectors  = $selectors;
              IsBreaking = $($groups.ContainsKey('break') -and $groups['break'].Success)
              Groups     = $groups;
            }

            # $pointer can point to either a hashtable or a List. If it currently points
            # to a hashtable, then we're only part way through the groupBy path. If pointer
            # points to a List, then we have reached the end of the path, the leaf. When
            # we reach the leaf, we have found where we need to add the commit to. So
            # we end up with multiple layers of hashes, where the leaf elements of the hashes
            # is an array of commits (bucket). All commits in the same bucket, possess
            # the same set of characteristics defined by the groupBy path.
            #
            [string]$path = $this._prefix;
            foreach ($segment in $this._segments) {
              # Set the selector from the commit fields
              #
              [string]$selector = if ($selectors.ContainsKey($segment)) {
                $selectors[$segment];
              }
              else {
                $this._uncategorised;
              }
              $path += "/$selector";

              if (-not($pointer.ContainsKey($selector))) {
                $pointer[$selector] = ($segment -eq $this._leafSegment) ? `
                  [System.Collections.Generic.List[PSCustomObject]]::new() : @{};
              }
              $pointer = $pointer[$selector];
            } # foreach ($segment in $this._segments)

            if ($pointer -is [System.Collections.Generic.List[PSCustomObject]]) {
              Write-Debug "    ~ '$path' Adding commit '$($com.Subject)'";
              $paths.Add($path);
              $pointer.Add($com);
            }
            else {
              throw "something went wrong, reached leaf, but is not a list '$($pointer)'"
            }
            $pointer = $partitions;
          } # foreach ($com in $commits)

          if (($commits.Count -eq 0) -and ($release)?.Dirty) {
            $partitions[$this._dirty] = $release.Dirty;
          }
        }

        # Since the commits have been flattened, it no longer reflects the buckets. This means
        # that when $paths is added to, commits may be multiple counted, because the same path
        # within a release could be added more than once.
        #
        $paths = $($paths | Get-Unique);

        $partitionItem = [PSCustomObject]@{
          PSTypeName = 'Loopz.ChangeLog.PartitionedRelease';
          Tag        = $tag;
          Partitions = $partitions;
          Paths      = $paths;
        }
        $partitioned.Add($partitionItem);

        if (($commits.Count -eq 0) -and ($release)?.Dirty) {
          Write-Debug "!!! Found '$($release.Dirty.Count)' DIRTY commits for release: '$($release.Label)'"
        }
      } # if ($releases.ContainsKey($tag.Label))
    } # foreach ($tag in $sortedTags)

    return $partitioned;
  } # Partition

  # $squashedRelease: [PSTypeName('Loopz.ChangeLog.SquashedRelease')]
  #
  # Returns: [PSTypeName('Loopz.ChangeLog.CommitInfo')][array]
  #
  [PSCustomObject[]] flatten([PSCustomObject]$squashedRelease) {

    [boolean]$selectLast = ($this.Options.Selection)?.Last -and $this.Options.Selection.Last;

    [System.Collections.Generic.List[PSCustomObject]]$squashed = `
      [System.Collections.Generic.List[PSCustomObject]]::new();

    if (($squashedRelease)?.Squashed -and $squashedRelease.Squashed.PSBase.Count -gt 0) {
      [string[]]$issues = $squashedRelease.Squashed.PSBase.Keys;

      foreach ($issue in $issues) {
        $item = $squashedRelease.Squashed[$issue];

        if ($item -is [PSCustomObject]) {
          $squashed.Add($item);
        }
        elseif ($item -is [System.Collections.Generic.List[PSCustomObject]]) {
          $squashed.Add($selectLast ? $item[-1] : $item[0]);
        }
        else {
          throw "flatten: found bad squashed item of type $($item.GetType()) for release: '$($squashedRelease.Label)'";
        }
      }
    }

    [PSCustomObject[]]$others = (($squashedRelease)?.Commits -and $squashedRelease.Commits.Count -gt 0) `
      ? $squashedRelease.Commits : @();

    [PSCustomObject[]]$flattened = $squashed + $others;

    return $flattened;
  } # flatten

  # The resultant array is designed only to be iterated, we don't need direct access to
  # each release
  #
  [PSCustomObject[]] SortReleasesByDate([hashtable]$releases, [PSCustomObject[]]$sortedTags) {

    [PSCustomObject[]]$sorted = foreach ($tagInfo in $sortedTags) {

      if ($releases.ContainsKey($tagInfo.Label)) {
        $releases[$tagInfo.Label]
      }
    }

    return $sorted;
  } # SortReleasesByDate

  [int[]] CountCommits([PSCustomObject[]]$sortedReleases) {
    [int]$squashed = -1;
    [int]$all = -1;

    foreach ($release in $sortedReleases) {
      if (($release)?.Commits) {
        $all += $release.Commits;
        $squashed += $release.Commits;
      }

      if (($release)?.Squashed) {
        $all += $release.Squashed.PSBase.Count;
        $squashed++;
      }
    }
    return $squashed, $all;
  } # CountCommits
} # GroupByImpl

# === [ ChangeLogGenerator ] ===================================================
#
class ChangeLogGenerator {
  [PSCustomObject]$Options;
  [SourceControl]$_sourceControl;
  [GroupBy]$_grouper;
  [string]$_baseUrl;

  ChangeLogGenerator([PSCustomObject]$options, [SourceControl]$sourceControl, [GroupBy]$grouper) {
    $this.Options = $options;
    $this._sourceControl = $sourceControl;
    $this._grouper = $grouper;
    $this._baseUrl = $this._sourceControl.ReadRemoteUrl();
  }

  [void] SetDescending([boolean]$value) {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (ChangeLogGenerator.SetDescending)');
  }

  [string] Generate([PSCustomObject[]]$releases) {
    throw [System.Management.Automation.MethodInvocationException]::new(
      'Abstract method not implemented (ChangeLogGenerator.Generate)');
  }
}

# === [ MarkdownChangeLogGenerator ] ===========================================
#
class MarkdownChangeLogGenerator : ChangeLogGenerator {
  [GeneratorUtils]$_utils;
  [boolean]$IsDescending = $true;

  MarkdownChangeLogGenerator(
    [PSCustomObject]$options, [SourceControl]$sourceControl, [GroupBy]$grouper
  ): base ($options, $sourceControl, $grouper) {

    [PSCustomObject]$generatorInfo = [PSCustomObject]@{
      PSTypeName = 'Loopz.ChangeLog.GeneratorInfo';
      #
      BaseUrl    = $this._baseUrl;
    }
    $this._utils = [GeneratorUtils]::new($options, $generatorInfo);
  } #ctor

  [void] SetDescending([boolean]$value) {
    $this.IsDescending = $value;
  }

  [string] Generate([PSCustomObject[]]$releases, [string]$template) {
    [System.Text.StringBuilder]$builder = [System.Text.StringBuilder]::new();

    [scriptblock]$OnCommit = {
      param(
        [System.Management.Automation.PSTypeName('Loopz.ChangeLog.SegmentInfo')]$segmentInfo,
        [System.Management.Automation.PSTypeName('Loopz.ChangeLog.CommitInfo')]$commit,
        [System.Management.Automation.PSTypeName('Loopz.ChangeLog.TagInfo')]$tagInfo,
        [GeneratorUtils]$utils,
        [System.Management.Automation.PSTypeName('Loopz.ChangeLog.WalkInfo')]$custom
      )
      [PSCustomObject]$output = $custom.Options.Output;
      [string]$commitStmt = $output.Statements.Commit;
      [hashtable]$commitVariables = $utils.GetCommitVariables($commit, $tagInfo);
      [string]$commitLine = $utils.Evaluate($commitStmt, $commit, $commitVariables);

      [void]$custom.Builder.AppendLine($commitLine);
    } # OnCommit

    [scriptblock]$OnEndBucket = {
      param(
        [System.Management.Automation.PSTypeName('Loopz.ChangeLog.SegmentInfo')]$segmentInfo,
        [System.Management.Automation.PSTypeName('Loopz.ChangeLog.TagInfo')]$tagInfo,
        [GeneratorUtils]$utils,
        [System.Management.Automation.PSTypeName('Loopz.ChangeLog.WalkInfo')]$custom
      )
      [PSCustomObject]$output = $custom.Options.Output;

      if (${output}?.Literals.BucketEnd -and -not([string]::IsNullOrEmpty($output.Literals.BucketEnd))) {
        [void]$custom.Builder.AppendLine([string]::Empty);
        [void]$custom.Builder.AppendLine($output.Literals.BucketEnd);
      }
    } # OnEndBucket

    [scriptblock]$OnHeading = {
      param(
        [string]$headingType,
        [string]$headingStmt,
        [System.Management.Automation.PSTypeName('Loopz.ChangeLog.SegmentInfo')]$segmentInfo,
        [System.Management.Automation.PSTypeName('Loopz.ChangeLog.WalkInfo')]$tagInfo,
        [GeneratorUtils]$utils,
        [System.Management.Automation.PSTypeName('Loopz.ChangeLog.WalkInfo')]$custom
      )
      [string]$prefix = [GeneratorUtils]::HeadingPrefix($headingType);
      if (-not($headingStmt.StartsWith($prefix))) {
        $headingStmt = $prefix + $headingStmt;
      }

      [hashtable]$headingVariables = $utils.GetHeadingVariables($segmentInfo, $tagInfo);
      [PSCustomObject]$commit = $null;
      [string]$headingLine = $utils.Evaluate($headingStmt, $commit, $headingVariables);

      [void]$custom.Builder.AppendLine($headingLine);
      [void]$custom.Builder.AppendLine([string]::Empty);
    } # OnHeading

    [PSCustomObject]$handlers = [PSCustomObject]@{
      PSTypeName = 'Loopz.ChangeLog.Handlers';
      Utils      = $this._utils;
    }

    $handlers | Add-Member -MemberType ScriptMethod -Name 'OnHeading' -Value $(
      $OnHeading
    );

    $handlers | Add-Member -MemberType ScriptMethod -Name 'OnCommit' -Value $(
      $OnCommit
    );

    $handlers | Add-Member -MemberType ScriptMethod -Name 'OnEndBucket' -Value $(
      $OnEndBucket
    );

    [string]$releaseFormat = $this.Options.Output.Headings.H2;

    if (-not($releaseFormat.StartsWith('## '))) {
      $releaseFormat = '## ' + $releaseFormat;
    }

    foreach ($release in $releases) {
      [string]$displayDate = $release.Tag.Date.ToString($this.Options.Output.Literals.DateFormat);
      [string]$displayTag = [GeneratorUtils]::TagDisplayName($release.Tag.Label);
      [string]$link = "[$($displayTag)]";

      [string]$releaseLine = $releaseFormat.Replace(
        [GeneratorUtils]::VariableSnippet('link'), $link).Replace(
        [GeneratorUtils]::VariableSnippet('tag'), $release.Tag.Label).Replace(
        [GeneratorUtils]::VariableSnippet('display-tag'), $displayTag).Replace(
        [GeneratorUtils]::VariableSnippet('date'), $displayDate
      );
      [void]$builder.AppendLine([string]::Empty);
      [void]$builder.AppendLine($releaseLine);
      [void]$builder.AppendLine([string]::Empty);

      [PSCustomObject]$customWalkInfo = [PSCustomObject]@{
        PSTypeName = 'Loopz.ChangeLog.WalkInfo';
        Builder    = $builder;
        Options    = $this.Options;
      }
      $this._grouper.Walk($release, $handlers, $customWalkInfo);
    }
    [string]$linksContent = $this.CreateComparisonLinks();
    [string]$warningsContent = $this.CreateDisabledWarnings();

    [string]$markdown = $template.Replace(
      '[[links]]', $linksContent
    ).Replace(
      '[[warnings]]', $warningsContent
    ).Replace(
      '[[content]]', $builder.ToString()
    );

    return $markdown;
  } # Generate

  [string] CreateComparisonLinks() {
    # should we only get the tags in range?
    #
    [PSCustomObject[]]$sortedTags = $this._sourceControl.ReadSortedTags($true, $this.IsDescending);
    [string]$baseUrl = $this._sourceControl.ReadRemoteUrl();

    [System.Text.StringBuilder]$builder = [System.Text.StringBuilder]::new();

    if ($sortedTags.Count -gt 1) {
      [PSCustomObject]$first, [PSCustomObject[]]$others = $sortedTags;

      foreach ($second in $others) {
        [string]$name = [GeneratorUtils]::TagDisplayName($first.Label);
        $builder.AppendLine(
          "[$($name)]: $($baseUrl)/compare/$($second.Label)...$($first.Label)"
        );

        $first = $second;
      }
    }

    return $builder.ToString();
  }

  [string] CreateDisabledWarnings() {

    [hashtable]$disabled = $this.Options.Output?.Warnings.Disable;

    [string]$content = if (($null -ne $disabled) -and $disabled.PSBase.Count -gt 0) {
      [System.Text.StringBuilder]$builder = [System.Text.StringBuilder]::new();
      [string[]]$warningCodes = $disabled.Keys;
      [string]$markdownFormat = "<!-- MarkDownLint-disable {0} -->";

      if ($warningCodes.Count -eq 1) {
        [void]$builder.AppendLine(
          $($markdownFormat -f $warningCodes[0])
        );
      }
      else {
        [string]$last = $warningCodes[-1];
        [string[]]$others = $warningCodes[0..$($warningCodes.Count - 2)];

        foreach ($code in $others) {
          [void]$builder.AppendLine(
            $($markdownFormat -f $code)
          );
        }
        [void]$builder.Append(
          $($markdownFormat -f $last)
        );
      }
      
      $builder.ToString();
    }
    else {
      [string]::Empty;
    }
    return $content;
  }
} # MarkdownChangeLogGenerator

# === [ GeneratorUtils ] =======================================================
#
class GeneratorUtils {
  [PSCustomObject]$Options;
  [PSCustomObject]$Output;
  [PSCustomObject]$GeneratorInfo;
  [regex]$_fieldRegex;

  static [string]$PREFIXES = '?!&^*+';
  static [hashtable]$_headings = @{
    'H3'    = '### ';
    'H4'    = '#### ';
    'Dirty' = '### ';
  };

  static [hashtable]$_lookups = @{
    '_A' = [PSCustomObject]@{
      PSTypeName = 'Loopz.ChangeLog.GeneratorUtils.Lookup';
      Instance   = 'Authors';
      Variable   = 'author';
    };

    '_C' = [PSCustomObject]@{
      PSTypeName = 'Loopz.ChangeLog.GeneratorUtils.Lookup';
      Instance   = 'ChangeTypes';
      Variable   = 'change';
    };


    '_S' = [PSCustomObject]@{
      PSTypeName = 'Loopz.ChangeLog.GeneratorUtils.Lookup';
      Instance   = 'Scopes';
      Variable   = 'scope';
    };

    '_T' = [PSCustomObject]@{
      PSTypeName = 'Loopz.ChangeLog.GeneratorUtils.Lookup';
      Instance   = 'Types';
      Variable   = 'type';
    };
  }

  GeneratorUtils([PSCustomObject]$options, [PSCustomObject]$generatorInfo) {
    $this.Options = $options;
    $this.Output = $options.Output;
    $this.GeneratorInfo = $generatorInfo;

    $this._fieldRegex = [regex]::new(
      "(?<prefix>[$([GeneratorUtils]::PREFIXES)])\{(?<symbol>[\w\-]+)\}"
    );
  }

  static [string] ConditionalSnippet([string]$value) {
    return "?{$value}";
  }

  static [string] LiteralSnippet([string]$value) {
    return "!{$value}";
  }

  static [string] LookupSnippet([string]$value) {
    return "&{$value}";
  }

  static [string] NamedGroupRefSnippet([string]$value) {
    return "^{$value}";
  }

  static [string] StatementSnippet([string]$value) {
    return "*{$value}";
  }

  static [string] VariableSnippet([string]$value) {
    return "+{$value}";
  }

  static [string] HeadingPrefix([string]$headingType) {
    return [GeneratorUtils]::_headings.ContainsKey($headingType) ? `
      [GeneratorUtils]::_headings[$headingType] : [string]::Empty;
  }

  static [string] AnySnippetExpression($value) {
    [string]$escaped = [regex]::Escape("{$value}");
    return "(?:[$([GeneratorUtils]::PREFIXES)])$($escaped)";
  }

  static [string] TagDisplayName([string]$label) {
    return $label -eq 'HEAD' ? 'Unreleased' : $label;
  }

  [string] AvatarImg([string]$username) {
    [string]$hostUrl = ($this.Options)?.SourceControl.HostUrl;
    [string]$size = ($this.Options)?.SourceControl.AvatarSize;
    [string]$imgElement = $(
      "<img title='$($username)' src='$($hostUrl)$($username).png?size=$($size)'>"
    );

    return $imgElement;
  }

  [string] CommitIdLink([PSCustomObject]$commit) {
    [string]$baseUrl = $this.GeneratorInfo.BaseUrl;
    [string]$fullHash = $commit.FullHash;

    [string]$link = $(
      "[$($commit.CommitId)]($($baseUrl)/commit/$fullHash)"
    );

    return $link;
  }

  [string] IssueLink([string]$issue) {
    [string]$baseUrl = $this.GeneratorInfo.BaseUrl;

    [string]$link = -not([string]::IsNullOrEmpty($baseUrl)) ? $(
      "[#$($issue)]($($baseUrl)/issues/$($issue))";
    ) : [string]::Empty;

    return $link;
  }

  [string] ThenReplaceStmt([string]$statement, [string]$symbol, [boolean]$condition, [string]$with) {
    [string]$symbolExpr = [GeneratorUtils]::AnySnippetExpression($symbol);
    [string]$replaced = ($condition) ? `
      $this.Output.Statements.$statement -replace $symbolExpr, $with : [string]::Empty;

    return $replaced;
  }

  [string] ThenReplaceStmt([string]$statement, [boolean]$condition, [string]$with) {
    [string]$replaced = ($condition) ? $this.Output.Statements.$statement : $with;

    return $replaced;
  }

  # conditional BreakStmt statement
  #
  [string] IfBreakStmt([PSCustomObject]$commit, [hashtable]$variables) {
    [string]$breakStmt = $this.ThenReplaceStmt(
      'Break',
      'break',
      (($commit) -and ($commit)?.Info -and $commit.Info.IsBreaking),
      $this.Output.Literals.Break
    );

    return $breakStmt;
  }

  # conditional ChangeStmt statement
  #
  [string] IfChangeStmt([PSCustomObject]$commit, [hashtable]$variables) {
    [string]$changeStmt = $this.ThenReplaceStmt(
      'Change',
      'change', 
      ($variables.ContainsKey('change')),
      $variables['change']
    );
    return $changeStmt;
  }

  # conditional SquashedStmt statement
  #
  [string] IfSquashedStmt([PSCustomObject]$commit, [hashtable]$variables) {
    [string]$squashedStmt = $this.ThenReplaceStmt(
      'Squashed',
      (($commit) -and ($commit)?.IsSquashed -and $commit.IsSquashed),
      [string]::Empty
    );
    return $squashedStmt;
  }

  # conditional IssueStmt statement
  #
  [string] IfIssueLinkStmt([PSCustomObject]$commit, [hashtable]$variables) {
    [string]$issueLinkStmt = $this.ThenReplaceStmt(
      'IssueLink',
      'issue-link',
      ($variables.ContainsKey('issue-link')),
      $variables['issue-link']
    );
    return $issueLinkStmt;
  }

  # conditional MetaStmt statement
  #
  [string] IfMetaStmt([PSCustomObject]$commit, [hashtable]$variables) {
    [string]$metaStmt = $this.Evaluate($this.Output.Statements.Meta, $commit, $variables);

    return [string]::IsNullOrEmpty($metaStmt) ? [string]::Empty : $metaStmt;
  }

  [hashtable] GetHeadingVariables([PSCustomObject]$segmentInfo, [PSCustomObject]$tagInfo) {

    [hashtable]$headingVariables = @{
      'date'        = $tagInfo.Date.ToString($this.Output.Literals.DateFormat);
      'display-tag' = [GeneratorUtils]::TagDisplayName($tagInfo.Label);
      'tag'         = $tagInfo.Label;
    }

    'change', 'scope', 'type' | ForEach-Object {
      if (${segmentInfo}?.$_) {
        $headingVariables[$_] = $segmentInfo.$_;
      }
    }

    return $headingVariables;
  }

  [hashtable] GetCommitVariables([PSCustomObject]$commit, [PSCustomObject]$tagInfo) {

    [hashtable]$commitVariables = @{
      'author'        = $commit.Author;
      'avatar-img'    = $this.AvatarImg($commit.Author);
      'date'          = $commit.Date.ToString($this.Output.Literals.DateFormat);
      'display-tag'   = [GeneratorUtils]::TagDisplayName($tagInfo.Label);
      'subject'       = $commit.Subject;
      'tag'           = $tagInfo.Label;
      'commitid'      = $commit.CommitId;
      'commitid-link' = $this.CommitIdLink($commit);
    }

    if (${commit}.Info -and $commit.Info.Groups['issue'] -and
      $commit.Info.Groups['issue'].Success) {
      [string]$issue = $commit.Info.Groups['issue'].Value;

      $commitVariables['issue'] = $issue;
      $commitVariables['issue-link'] = $this.IssueLink($issue);
    }

    if (${commit}?.Info) {
      'change', 'scope', 'type' | ForEach-Object {
        if ($commit.Info.Selectors.ContainsKey($_)) {
          $commitVariables[$_] = $commit.Info.Selectors[$_];
        }
      }
    }

    return $commitVariables;
  } # GetCommitVariables

  [string] Evaluate(
    [string]$source,
    [PSCustomObject]$commit,
    [hashtable]$variables) {

    [string[]]$trail = @();
    [string]$statement = $this.evaluateStmt($source, $commit, $variables, $trail);
    return $this.ClearUnresolvedFields($statement);
  } # Evaluate

  [string] evaluateStmt([string]$source,
    [PSCustomObject]$commit,
    [hashtable]$variables,
    [string[]]$trail) {

    [string]$result = if ($this._fieldRegex.IsMatch($source)) {
      [System.Text.RegularExpressions.MatchCollection]$mc = $this._fieldRegex.Matches($source);

      [string]$evolve = $source;
      foreach ($m in $mc) {
        [System.Text.RegularExpressions.GroupCollection]$groups = $m.Groups;

        if ($groups['prefix'].Success -and $groups['symbol'].Success) {
          [string]$prefix = $groups['prefix'].Value;
          [string]$symbol = $groups['symbol'].Value;

          if ($trail -notContains $symbol) {

            [string]$target, [string]$with = switch ($prefix) {
              '*' {
                [string]$snippet = [GeneratorUtils]::StatementSnippet($symbol);
                $trail += $symbol;

                if ($evolve.Contains($snippet)) {
                  [string]$property = $symbol -replace 'Stmt';

                  if ($this.Output.Statements.psobject.properties.match($property).Count -eq 0) {
                    throw [System.Management.Automation.MethodInvocationException]::new(
                      "GeneratorUtils.evaluateStmt(bad options config): " +
                      "'$($symbol)' is not a defined Statement");
                  }

                  [string]$statement = $this.Output.Statements.$property;
                  [string]$replacement = $this.evaluateStmt(
                    $statement, $commit, $variables, $trail
                  );

                  $snippet, $replacement
                }
                break;
              }

              '?' {
                [string]$snippet = [GeneratorUtils]::ConditionalSnippet($symbol);
                $trail += $symbol;

                if ($evolve.Contains($snippet)) {
                  [string]$replacement = try {
                    $this."If$symbol"($commit, $variables);
                  }
                  catch {
                    throw [System.Management.Automation.MethodInvocationException]::new(
                      "GeneratorUtils.evaluateStmt(bad options config): " +
                      "'$($symbol)' is not a defined conditional statement");
                  }

                  # we need to recurse here just in-case the expansion has resulted in
                  # unresolved references.
                  #
                  $replacement = $this.evaluateStmt(
                    $replacement, $commit, $variables, $trail
                  );

                  $snippet, $replacement
                }
                break;
              }

              '!' {
                [string]$snippet = [GeneratorUtils]::LiteralSnippet($symbol);

                if ($evolve.Contains($snippet)) {

                  if ($this.Output.Literals.psobject.properties.match($symbol).Count -eq 0) {
                    throw [System.Management.Automation.MethodInvocationException]::new(
                      "GeneratorUtils.evaluateStmt(bad options config): " +
                      "'$($symbol)' is not a defined Literal"
                    );
                  }
                  [string]$replacement = $this.Output.Literals.$symbol;
                  $snippet, $replacement
                }
                break;
              }

              '&' {
                [string]$snippet = [GeneratorUtils]::LookupSnippet($symbol);

                if ($evolve.Contains($snippet)) {
                  if (-not([GeneratorUtils]::_lookups.ContainsKey($symbol))) {
                    throw [System.Management.Automation.MethodInvocationException]::new(
                      $(
                        "GeneratorUtils.Evaluate(bad options config): " +
                        "Lookup '$symbol' not found"
                      )
                    );
                  }

                  [string]$instance = [GeneratorUtils]::_lookups[$symbol].Instance;
                  [string]$variable = [GeneratorUtils]::_lookups[$symbol].Variable;
                  [string]$seek = $variables[$variable];

                  [string]$replacement = (
                    $this.Output.Lookup.$instance.ContainsKey($seek)) ? `
                    $this.Output.Lookup.$instance[$seek] : $this.Output.Lookup.$instance['?'];

                  $snippet, $replacement
                }
                break;
              }

              '^' {
                [string]$snippet = [GeneratorUtils]::NamedGroupRefSnippet($symbol);

                if ($evolve.Contains($snippet)) {
                  [string]$replacement = if (($commit)?.Info.Groups -and `
                      $commit.Info.Groups[$symbol].Success) {
                    $commit.Info.Groups[$symbol].Value;
                  }
                  else {
                    [string]::Empty;
                  }

                  $snippet, $replacement
                }
                break;
              }

              '+' {
                [string]$snippet = [GeneratorUtils]::VariableSnippet($symbol);

                if ($evolve.Contains($snippet)) {
                  [string]$replacement = ($variables.ContainsKey($symbol)) `
                    ? $variables[$symbol]: [string]::Empty;

                  $snippet, $replacement
                }
                break;
              }
            }
            $evolve = $evolve.Replace($target, $with);
          }
          else {
            throw [System.Management.Automation.MethodInvocationException]::new(
              $(
                "GeneratorUtils.Evaluate(bad options config): " +
                "statement: '$source' contains circular reference: '$symbol'"
              )
            );
          }
        }
        else {
          throw [System.Management.Automation.MethodInvocationException]::new(
            $(
              "GeneratorUtils.Evaluate(prefix/symbol): " +
              "statement: '$source' contains failed group references"
            )
          );
        }
      }
      $evolve;
    }
    else {
      $source;
    }

    return $result;
  } # evaluateStmt

  [string] ClearUnresolvedFields($value) {
    return $this._fieldRegex.Replace($value, '');
  }
} # GeneratorUtils
