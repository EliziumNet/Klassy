
function get-CurrentTime {
  param(
    [string]$Format = 'dd-MMM-yyyy'
  )
  return Get-Date -Format $Format;
}
