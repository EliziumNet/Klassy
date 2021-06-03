
function New-ChangeLog {
  <#
  .NAME
    New-ChangeLog

  .SYNOPSIS
    Create ChangeLog instance

  .DESCRIPTION
    Factory function for ChangeLog instances.

  .LINK
    https://eliziumnet.github.io/klassy

  .PARAMETER Options
    ChangeLog options
  #>
  [OutputType([ChangeLog])]
  param(
    [PSCustomObject]$Options
  )
  [SourceControl]$git = [Git]::new($Options);
  [GroupByImpl]$grouper = [GroupByImpl]::new($Options);
  [MarkdownChangeLogGenerator]$generator = [MarkdownChangeLogGenerator]::new(
    $Options, $git, $grouper
  );
  [ChangeLog]$instance = [ChangeLog]::new($Options, $git, $grouper, $generator);

  $instance.Init();
  return $instance;
}
