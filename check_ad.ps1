#
# check_ad.ps1
#
# based on the old check_ad.vbs script - https://exchange.nagios.org/directory/Plugins/Operating-Systems/Windows/Active-Directory-(AD)-Check/details
#

$debug = $false

function dt {
  Param ($txtp)
  if ($debug) {
    write-host($txtp)
  }
}      

function parse {
  Param ($txtp)
  # Convert tabs to spaces and remove superfluous characters 
  #$txtp = $txtp -replace "[`n`r]", ""
  $txtp = $txtp -replace "`t", " "
  $txtp = $txtp -replace "\s+", " "
  dt("txtp=$txtp")
  # Iterate through the list of checks for this line until we get a match
  $matched=$false
  $i=0
  while ((!$matched) -and ($i -lt $name.count)) {
    If ($txtp -match "passed test (?<test>.*)") {
      $test=$matches['test']
      dt("Checking ""$txtp"" as it contains 'passed test $test'")
      foreach ($strname in $name[$i]) {
        dt("strname:$strname")
        # we test this way round so that "dns /dnsbasic" matches "dns"
        if ($strname -match $test) {
          if (!$lock[$i]) { 
            $status[$i]="OK"
            dt("Set the status for test $($name[$i]) to $($status[$i])")
          }
          $matched=$true
        }
      }
    }
    # if we find the "failed" string then reset to CRITICAL
    ElseIf ($txtp -match "failed test (?<test>.*)") {
      #What are we testing for now?
      $test=$matches['test']
      dt("Checking ""$txtp"" as it contains 'failed test $test'")
      foreach ($strname in $name[$i]) {
        if ($strname -match $test) { 
          $status[$i]="CRITICAL"
          #Lock the variable so it can't be reset back to success. Required for multi-partition tests like dns and fsmocheck
          $lock[$i]=$true
          dt("Reset the status for test $($name[$i]) to $($status[$i]) with a lock $($lock[$i])")
          $matched=$true
        }
      }
    }
    $i++
  }
}   

$res=Import-Module ActiveDirectory -passthru -ea 0
if ($res -eq $null) {
  write-host "UNKNOWN - Cannot load ActiveDirectory Module"
  exit 3
}

$rodc=(Get-ADDomainController).isreadonly
$status=@()
$lock=@()
$name = @("connectivity", "services", "replications", "advertising", "fsmocheck")
# don't try RIDManager tests on Read-only DCs
if (!$rodc) {
  $name += "ridmanager"
}
$name += @("machineaccount", "kccevent", "sysvolcheck", "dns /dnsbasic")

$cmd = "c:\windows\system32\dcdiag.exe"
$params=""
# Set default status for each named test
for ($i=0; $i -lt $name.count; $i++) {
  $status += "CRITICAL"
  $lock += $false
  $params += "/test:$($name[$i]) "
}
# split parameters into a form powershell can pass as parameters
$parms=$params.split(" ")
# run dcdiag command
$res=& $cmd $parms
if ($debug) {
  $res
}
$lineout=""
# find test results and parse them
ForEach ($line in $res) {
  # Parse an output line from dcdiag command and change state of checks
  dt("input line: ""$line""")
  if ($line -match "\.\.\.\.\.") { 
    #testresults start with a couple of dots, reset the lineout buffer
    $lineout=$line
    dt("lineout buffer: ""$lineout""")
    #do not test it yet as it may be split over two lines
  } else {
    # Else append the next line to the buffer to capture multiline responses
    if ($lineout -match "\.\.\.\.\.") {
      $lineout += $line
      dt("lineout buffer appended: ""$lineout""")
      # test line as we've now appended any overflow
      if (($lineout -match "passed test") -or ($lineout -match "failed test")) {
        #we have a strOK String which means we have reached the end of a result output (maybe on newline)
        dt("parsing: ""$lineout""")
        parse($lineout)
        if ($line -ne "") {
          $lineout = ""
        }
      }
    }
  }  
}
# Catch the very last test (may be in the lineout buffer but not yet processed)
if ( ($lineout -match "passed test") -or ($lineout -match "failed test") ) {
  #we have a strOK String which means we have reached the end of a result output (maybe on newline)
  dt("last lineout: ""$lineout""")
  parse($lineout)
}

#output result for NAGIOS
$msg=""
for ($i = 0; $i -lt $name.count; $i++) {
  $msg += "$($name[$i]): $($status[$i]). "
}
if ($msg -match "CRITICAL") {
  write-host "CRITICAL - $msg"
  exit 2
} else {
  write-host "OK - $msg"
  exit 0
}
