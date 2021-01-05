
function get-CurrentTime {
  param(
    [string]$Format = 'dd-MMM-yyyy-HH-mm-ss'
  )
  return Get-Date -Format $Format;
}
