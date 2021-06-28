#==============================================================================================
#Pre-requisites

#Local PVS SOAP service must be running in order to execute MCLI
if ((Get-Service -Name "soapserver").Status -ne "Running") {
    write-host "MCLI Snapin depends on the Citrix PVS SOAP service - this service is currently stopped" -Foregroundcolor Red
    exit
}

Local Web Client service must be running in order to save to Collaborate / Sharepoint site
$wc = Get-Service | where-object {$_.Name -eq "webclient"}
if ($wc -ne $null){
    if ($wc.status  -ne "Running") {
        Set-Service webclient -StartupType Manual
        Start-Service webclient   
        }
    }
else {
    write-host "Web Client service must be running to save report to Collaborate - you may need to install Desktop Experience" -Foregroundcolor Red
    exit
    }


#The MCLI Snapin is required for provisioning server scripts to run
$snapInCheck = Get-PSSnapin | Where-Object { $_.name -eq "McliPSSnapin"}
if ($snapInCheck -eq $null ) {
    & "C:\Windows\Microsoft.NET\Framework64\v2.0.50727\installutil.exe" "E:\vendor_apps\Citrix\Provisioning Services Console\mclipssnapin.dll"
    Add-PSSnapin mcliPSSnapin
}

# this line retrieves the PVs FARM info, it is returned as an ONE array of strings for the full farm.
$farmInfo = mcli-get farm | Where-Object { $_.toLower().contains("farmname")}
$farmName = $farmInfo.replace("farmName: ","")

$now=(get-date -format ddMMMyyyy_HHmm).ToString()
$today = get-date

#====================================================
#==========================================
# Set these variables to customise to the environment the script runs in
# Change this variable to point at the PVS Store where the vDisks are held.
$PVSStore = "F$\PVSStore"

$saveTo ="\\collaborate.statestr.com\sites\Citrix\Changes and Issues Reports\Daily Health Check"


#set retention period for reports
$retentionDays = 90

#Use these variables to determine which actions are classed as RED or AMBER
# These will then be highlighted on the report.
$arrRedAuditActions = "1002", "1003", "1016", "1008", "1009", "1010"
$arrAmberAuditActions = "2007", "2049", "2051"

#How many days audit history needs retrieved
#TESTPURPOSES - set to 1 when switches to production
$auditRetrievalDays = 7

#==============================================================================================

#Create table that maps action codes to names
$auditCodeNameMapping = @{}
$auditCodeNameMapping.add("2","Add Collection")
$auditCodeNameMapping.add("3","Add Device")
$auditCodeNameMapping.add("4","Add DiskLocator")
$auditCodeNameMapping.add("7","Add Site")
$auditCodeNameMapping.add("8","Add SiteView")
$auditCodeNameMapping.add("1002","Delete Collection")
$auditCodeNameMapping.add("1003","Delete Device")
$auditCodeNameMapping.add("1005","Delete DiskLocator")
$auditCodeNameMapping.add("1016","Delete DiskVersion")
$auditCodeNameMapping.add("1008","Delete ServerStore")
$auditCodeNameMapping.add("1009","Delete Site")
$auditCodeNameMapping.add("1010","Delete SiteView")
$auditCodeNameMapping.add("2001","Run AddDeviceToDomain")
$auditCodeNameMapping.add("2006","Run AssignDevice")
$auditCodeNameMapping.add("2007","Run AssignDiskLocator")
$auditCodeNameMapping.add("2009","Run Book")
$auditCodeNameMapping.add("2055","Run ExportDisk")
$auditCodeNameMapping.add("2049","Run MergeDisk")
$auditCodeNameMapping.add("2051","Run PromoteDiskVersion")
$auditCodeNameMapping.add("2036","Run RemoveDeviceFromDomain")
$auditCodeNameMapping.add("2039","Run ResetDeviceForDomain")
$auditCodeNameMapping.add("2042","Run RunShutdown")
$auditCodeNameMapping.add("2046","Run UnlockDisk")
$auditCodeNameMapping.add("3001","RunWithReturn CreateDisk")
$auditCodeNameMapping.add("3005","RunWithReturn CreateMaintenanceVersion")
$auditCodeNameMapping.add("3004","RunWithReturn RebalanceDevices")
$auditCodeNameMapping.add("6002","Set Collection")
$auditCodeNameMapping.add("6003","Set Device")
$auditCodeNameMapping.add("6004","Set Disk")
$auditCodeNameMapping.add("6005","Set DiskLocator")
$auditCodeNameMapping.add("6016","Set DiskVersion")
$auditCodeNameMapping.add("6008","Set Server")
$auditCodeNameMapping.add("6011","Set ServerStore")

#$auditCodeNameMapping
#==============================================================================================
$currentDir = Split-Path $MyInvocation.MyCommand.Path

#Create subfolder for each environment
if ($farmname.toLower().contains("dev")){
    $saveToFarm = -join($saveTo,"\DEV\PVS\",$farmName)
}
elseif ($farmname.toLower().contains("uat")){
    $saveToFarm = -join($saveTo,"\UAT\PVS\",$farmName)
}
else {
    $saveToFarm = -join($saveTo,"\PROD\PVS\",$farmName)
}
md -force $saveToFarm

#(-join ($farmName,"_XAServerHealthCheck", $now, ".log"))

$logfile    = Join-Path $saveToFarm ("PVSServerHealthCheck.log")
$resultsHTM = Join-Path $saveToFarm ("PVSServerHealthCheckResults.htm")
$errorsHTM  = Join-Path $saveToFarm ("PVSServerHealthCheckErrors.htm")
$resultsNowHTM = Join-Path $saveToFarm (-join($now,"PVSServerHealthCheckResults.htm"))


#==============================================================================================

if ((Get-PSSnapin "McliPSSnapIn" -EA silentlycontinue) -eq $null) {
try { Add-PSSnapin McliPSSnapIn -ErrorAction Stop }
catch { write-error "Error loading PVS McliPSSnapIn PowerShell snapin"; Return }
}
# Change the below variables to suit your environment
#==============================================================================================
# Target Device Health Check threshold:
$retrythresholdWarning= "15" # define the Threshold from how many retries the color switch to red
$drivespacewarning = "20"
$drivespsaceerror = "10"

# Include for Device Collections, type "every" if you want to see every Collection 
# Example1: $Collections = @("XA65","XA5")
# Example2: $Collections = @("every")
$Collections = @("every")
 
# Information about the site you want to check:
$siteName="site" # site name on which the according Store is.
  
# E-mail report details
$emailFrom = "email@company.ch"
$emailTo = "citrix@company.ch"#,"sacha.thomet@appcloud.ch"
$smtpServer = "mailrelay.company.ch"
$emailSubjectStart = "PVS Farm Report"
$mailprio = "High"
#==============================================================================================
 
 
#Header for Table 1 "Target Device Checks"
$TargetfirstheaderName = "TargetDeviceName"
$TargetheaderNames = "CollectionName", "Ping", "Retry", "vDisk_PVS", "vDisk_Version", "WriteCache", "PVSServer"
$TargetheaderWidths = "4", "4", "4", "4", "2" , "4", "4"
$Targettablewidth = 1200
#Header for Table 2 "vDisk Checks"
$vDiksFirstheaderName = "vDisk"
$vDiskheaderNames = "Store", "vDiskFileName", "deviceCount", "CreateDate" , "ReplState", "LoadBalancingAlgorithm", "WriteCacheType"
$vDiskheaderWidths = "4", "8", "2","4", "4", "4", "4"
$vDisktablewidth = 1200
#Header for Table 3 "PV Server"
$PVSfirstheaderName = "PVS Server"
$PVSHeaderNames = "Ping", "Active", "deviceCount","SoapService","StreamService","TFTPService","CDrive","EDrive","FDrive"
$PVSheaderWidths = "4", "4", "4","4","4","4","4","4","4"
$PVStablewidth = 800
#Header for Table 4 "Farm"
$PVSFirstFarmheaderName = "FarmChecks"
$PVSFarmHeaderNames = "Setting", "Value"
$PVSFarmWidths = "4", "8", "8"
$PVSFarmTablewidth = 400
#Header for Table 5 Audit
$PVSFirstAuditHeaderName = "Time"
$PVSAuditHeaderNames = "Time", "Action", "Object", "ID"
$PVSAuditWidths =   "6",        "8",   "4",   "4"
$PVSAuditTableWidth = 800

$siteHashTable = @{}
#$auditTrailHashTable = @{}
$REDauditTrailHashTable = @{}
$AMBERauditTrailHashTable = @{}
$GREENauditTrailHashTable = @{}
$ALLauditTrailHashTable=@{}


#Functions for use:
function convertDate($aDate){
    #this function takes the long date formats and convers to yyyy/mm/ddd format.
    $dayNum = "{0:d2}" -f ($aDate.day)
    $monthNum = "{0:d2}" -f ($aDate.month)
    $yearNum = $aDate.year
    $convertedDate = -join($yearNum,"/",$monthNum,"/",$dayNum)
    $convertedDate
}
function getAuditTrail {
    # takes output from audittrail (which is an array with each line a distinct record) to 
    # a hash table where each audit action becomes a record.
    param($arrayOfStringsAT)
             
    # As it is one array, you have to read it line by line, to pull out the audit trail items we wish to 
    # report on
    $arrayOfStringsAT | forEach-object {
        if ($_.toLower().contains("record #")){
            $n = $_.substring(8)
            $auditRecord = [int]$n
            $auditAction = $null
            $auditTime = $null
            $auditUserID = $null
            $auditObject = $null
            $auditCategory = $null
            $control = 0
            }
        elseif ($_.toLower().contains("time:")){
            $auditTime = $_.substring(6)
            $control = $control + 1
            #$auditTime
            }
        elseif ($_.toLower().contains("username:")){
            $auditUserID = $_.substring(10)
            $control = $control + 1
            #$auditUserID
            }
        elseif ($_.toLower().contains("action:")){
            $AuditActionCode = $_.substring(8)
            $control = $control + 1
            #$auditAction
            
            #now check the action codes against the arrays that determine category
            if ($arrRedAuditActions -Contains($AuditActionCode)){
                $auditCategory = "RED"
                $control = $control + 1
                }
            elseif ($arrAmberAuditActions -Contains($AuditActionCode)){
                $auditCategory = "AMBER"
                $control = $control + 1
                }
            else {
                $auditCategory = "GREEN"
                $control = $control + 1
                }
            #$auditCategory
            try {
                $auditAction = $auditCodeNameMapping.$auditActionCode
				}
			catch {
				$auditAction = "Unknown Action"
			    }
            
            #$auditAction
            }
        elseif ($_.toLower().contains("objectname:")){
            $auditObject = $_.substring(6)
            $control = $control + 1
            #$auditObject
            if ($control -eq 5) {
                #create a hashtable for each record
                $auditRecordHashTable=@{}
                $auditRecordHashTable.add("Action", $auditAction)
                $auditRecordHashTable.add("Time", $auditTime)
                $auditRecordHashTable.add("ID", $auditUserID)
                $auditRecordHashTable.add("Object", $auditObject)
                $auditRecordHashTable.add("Category", $auditCategory)
                #add the individual record hashtable to the full audit trail hashtable
                $ALLauditTrailHashTable.add($auditRecord,$auditRecordHashTable)
               
               <#
                #@@@@@@@@@@@@@@ could just collapse so added to one table
                if ($auditCategory -eq "RED"){
                    $REDauditTrailHashTable.add($auditRecord,$auditRecordHashTable)
                    }
                elseif($auditCategory -eq "AMBER"){
                    $AMBERauditTrailHashTable.add($auditRecord,$auditRecordHashTable)
                    }
                else {
                    $GREENauditTrailHashTable.add($auditRecord,$auditRecordHashTable)
                    }
                    #>
            
               }
            }

    }
}
#==============================================================================================
#log function
function LogMe() {
Param(
[parameter(Mandatory = $true, ValueFromPipeline = $true)] $logEntry,
[switch]$display,
[switch]$error,
[switch]$warning,
[switch]$progress
)
 
 if ($error) {
$logEntry = "[ERROR] $logEntry" ; Write-Host "$logEntry" -Foregroundcolor Red}
elseif ($warning) {
Write-Warning "$logEntry" ; $logEntry = "[WARNING] $logEntry"}
elseif ($progress) {
Write-Host "$logEntry" -Foregroundcolor Green}
elseif ($display) {
Write-Host "$logEntry" }
  
 #$logEntry = ((Get-Date -uformat "%D %T") + " - " + $logEntry)
$logEntry | Out-File $logFile -Append
}
#==============================================================================================
function Ping([string]$hostname, [int]$timeout = 200) {
$ping = new-object System.Net.NetworkInformation.Ping #creates a ping object
try {
$result = $ping.send($hostname, $timeout).Status.ToString()
} catch {
$result = "Failure"
}
return $result
}
#==============================================================================================
Function writeHtmlHeader
{
param($title, $fileName)
$date = ( Get-Date -format R)
$head = @"
<html>
<head>
<meta http-equiv='Content-Type' content='text/html; charset=iso-8859-1'>
<title>$title</title>
<STYLE TYPE="text/css">
<!--
td {
font-family: Tahoma;
font-size: 11px;
border-top: 1px solid #999999;
border-right: 1px solid #999999;
border-bottom: 1px solid #999999;
border-left: 1px solid #999999;
padding-top: 0px;
padding-right: 0px;
padding-bottom: 0px;
padding-left: 0px;
overflow: hidden;
}
body {
margin-left: 5px;
margin-top: 5px;
margin-right: 0px;
margin-bottom: 10px;
table {
table-layout:fixed; 
border: thin solid #000000;
}
-->
</style>
</head>
<body>
<table width='1200'>
<tr bgcolor='#CCCCCC'>
<td colspan='7' height='48' align='center' valign="middle">
<font face='tahoma' color='#003399' size='4'>
<strong>$title - $date</strong></font>
</td>
</tr>
</table>
"@
$head | Out-File $fileName
}
# ==============================================================================================
Function writeTableHeader
{
param($fileName, $firstheaderName, $headerNames, $headerWidths, $tablewidth)
$tableHeader = @"
<table width='$tablewidth'><tbody>
<tr bgcolor=#CCCCCC>
<td width='6%' align='center'><strong>$firstheaderName</strong></td>
"@
$i = 0
while ($i -lt $headerNames.count) {
$headerName = $headerNames[$i]
$headerWidth = $headerWidths[$i]
$tableHeader += "<td width='" + $headerWidth + "%' align='center'><strong>$headerName</strong></td>"
$i++
}
$tableHeader += "</tr>"
$tableHeader | Out-File $fileName -append
}
# ==============================================================================================
Function writeTableFooter
{
param($fileName)
"</table><br/>"| Out-File $fileName -append
}
#==============================================================================================
Function writeData
{
param($data, $fileName, $headerNames)
  
 $data.Keys | sort | foreach {
$tableEntry += "<tr>"
$computerName = $_
$tableEntry += ("<td bgcolor='#CCCCCC' align=center><font color='#003399'>$computerName</font></td>")
#$data.$_.Keys | foreach {
$headerNames | foreach {
#"$computerName : $_" | LogMe -display
try {
if ($data.$computerName.$_[0] -eq "SUCCESS") { $bgcolor = "#387C44"; $fontColor = "#FFFFFF" }
elseif ($data.$computerName.$_[0] -eq "WARNING") { $bgcolor = "#FF7700"; $fontColor = "#FFFFFF" }
elseif ($data.$computerName.$_[0] -eq "ERROR") { $bgcolor = "#FF0000"; $fontColor = "#FFFFFF" }
else { $bgcolor = "#CCCCCC"; $fontColor = "#003399" }
$testResult = $data.$computerName.$_[1]
}
catch {
$bgcolor = "#CCCCCC"; $fontColor = "#003399"
$testResult = ""
}
  
 $tableEntry += ("<td bgcolor='" + $bgcolor + "' align=center><font color='" + $fontColor + "'>$testResult</font></td>")
}
  
 $tableEntry += "</tr>"
  
  
 }
  
 $tableEntry | Out-File $fileName -append
}
# ==============================================================================================
Function writeHtmlFooter
{
param($fileName)
@"
<table>
<table width='1200'>
<tr bgcolor='#CCCCCC'>
<td colspan='7' height='25' align='left'>
<br>
<font face='courier' color='#000000' size='2'><strong>Retry Threshold =</strong></font><font color='#003399' face='courier' size='2'> $retrythresholdWarning<tr></font><br>
<tr bgcolor='#CCCCCC'>
</td>
</tr>
<tr bgcolor='#CCCCCC'>
</tr>
</table>
</body>
</html>
"@ | Out-File $FileName -append
}
 
#==============================================================================================
# == MAIN SCRIPT ==
#==============================================================================================
rm $logfile -force -EA SilentlyContinue
"Begin with Citrix Provisioning Services HealthCheck" | LogMe -display -progress
" " | LogMe -display -progress
 
  
 
# ======= PVS Target Device Check ========
"Check PVS Target Devices" | LogMe -display -progress
" " | LogMe -display -progress
$allResults = @{}
$pvsdevices = mcli-get device -f deviceName | Select-String deviceName
foreach($target in $pvsdevices)
 {
  
 $tests = @{} 
  
 # Check to see if the server is in an excluded folder path
$target | Select-String deviceName 
 $_targetshort = $target -replace "deviceName: ",""
 $pvcollectionName = mcli-get deviceinfo -p devicename=$_targetshort | select-string collectionName
$short_collectionName = $pvcollectionName.ToString().TrimStart("collectionName: ")
  
 #Only Check Servers in defined Collections: 
 if ($Collections -contains $short_collectionName -Or $Collections -contains "every") { 
  
 
 $target | Select-String deviceName 
 $_targetshort = $target -replace "deviceName: ",""
$_targetshort | LogMe -display -progress
  
 # Ping server 
 $result = Ping $_targetshort 100
if ($result -ne "SUCCESS") { $tests.Ping = "ERROR", $result }
else { $tests.Ping = "SUCCESS", $result 
 }
  
 #CollectionName
$pvcollectionName = mcli-get deviceinfo -p devicename=$_targetshort | select-string collectionName
$short_collectionName = $pvcollectionName.ToString().TrimStart("collectionName: ")
$tests.CollectionName = "NEUTRAL", "$short_collectionName"
 # Test Retries
$devicestatus = mcli-get deviceinfo -p devicename=$_targetshort -f status
$retrycount = $devicestatus[4].TrimStart("status: ") -as [int]
if ($retrycount -lt $retrythresholdWarning) { $tests.Retry = "SUCCESS", "$retrycount Retry = OK" }
else { $tests.Retry = "WARNING","$retrycount retries!" }
  
 #Check assigned Image
$devicediskFileName = mcli-get deviceinfo -p devicename=$_targetshort | select-string diskFileName
$short_devicediskFileName = $devicediskFileName.ToString().TrimStart("diskFileName: ")
$tests.vDisk_PVS = "SUCCESS", "$short_devicediskFileName"
 #Check assigned Image Version
$devicediskVersion = mcli-get deviceinfo -p devicename=$_targetshort | select-string diskVersion:
$short_devicediskVersion = $devicediskVersion.ToString().TrimStart("diskVersion: ")
$tests.vDisk_Version = "SUCCESS", "$short_devicediskVersion"
 #PVS-Server
$PVSServername = mcli-get deviceinfo -p devicename=$_targetshort | select-string serverName
$short_PVSServername = $PVSServername.ToString().TrimStart("serverName: ")
$tests.PVSServer = "Neutral", "$short_PVSServername"


################ PVS WriteCache SECTION ###############

		
		if (test-path \\$_targetshort\c$\Personality.ini)
		{

			$wconhd = ""
			$wconhd = Get-Content \\$_targetshort\c$\Personality.ini | Where-Object  {$_.Contains("WriteCacheType=4") }
			
			If ($wconhd -match "$WriteCacheType=4") {Write-Host Cache on HDD
			
			#WWC on HD is $wconhd

				# Relative path to the PVS vDisk write cache file
				$PvsWriteCache   = "d$\.vdiskcache"
				# Size of the local PVS write cache drive
				$PvsWriteMaxSize = 30gb # size in GB
			
				$PvsWriteCacheUNC = Join-Path "\\$_targetshort" $PvsWriteCache 
				$CacheDiskexists  = Test-Path $PvsWriteCacheUNC
				if ($CacheDiskexists -eq $True)
				{
					$CacheDisk = [long] ((get-childitem $PvsWriteCacheUNC -force).length)
					$CacheDiskGB = "{0:n2}GB" -f($CacheDisk / 1GB)
					"PVS Cache file size: {0:n2}GB" -f($CacheDisk / 1GB) | LogMe
					#"PVS Cache max size: {0:n2}GB" -f($PvsWriteMaxSize / 1GB) | LogMe -display
					if($CacheDisk -lt ($PvsWriteMaxSize * 0.5))
					{
					   "WriteCache file size is low" | LogMe
					   $tests.WriteCache = "SUCCESS", $CacheDiskGB
					}
					elseif($CacheDisk -lt ($PvsWriteMaxSize * 0.8))
					{
					   "WriteCache file size moderate" | LogMe -display -warning
					   $tests.WriteCache = "WARNING", $CacheDiskGB
					}   
					else
					{
					   "WriteCache file size is high" | LogMe -display -error
					   $tests.WriteCache = "ERORR", $CacheDiskGB
					}
				}              
			   
				$Cachedisk = 0
			   
				$VDISKImage = get-content \\$_targetshort\c$\Personality.ini | Select-String "Diskname" | Out-String | % { $_.substring(12)}
				if($VDISKImage -Match $DefaultVDISK){
					"Default vDisk detected" | LogMe
					$tests.vDisk = "SUCCESS", $VDISKImage
				} else {
					"vDisk unknown"  | LogMe -display -error
					$tests.vDisk = "SUCCESS", $VDISKImage
				}   
			
			}
			else 
			{Write-Host Cache on Ram
			
			#RAMCache
			#Get-RamCache from each target, code from Matthew Nics http://mattnics.com/?p=414
			$RAMCache = [math]::truncate((Get-WmiObject Win32_PerfFormattedData_PerfOS_Memory -ComputerName $_targetshort).PoolNonPagedBytes /1MB)
			$tests.WriteCache = "Neutral", "$RamCache MB on Ram"
		
			}
		
		}
		else 
		{Write-Host WriteCache not readable
		$tests.WriteCache = "Neutral", "Cache not readable"	
		}
		############## END PVS WriteCache SECTION #############
			

#Forward results to $allResult array which will be written in HTM-File
$allResults.$_targetshort = $tests
 }
}

$sites = mcli-get site -f sitename
$vdiskResults = @{}
foreach ($site in $sites)
{
if ($site -like "siteName: *")
{
write-host $site
write-host "after replacing"
$sitename = $site.replace("siteName: ","")
write-host $sitename

# ======= PVS vDisk Check #==================================================================
"Check PVS vDisks" | LogMe -display -progress
" " | LogMe -display -progress
 
$storenames = mcli-get store | Select-string storename

foreach ($storenameA in $storenames)
{
$storename = $storenameA -replace "storename: ",""
$storeid = mcli-get store -p storeName=$storename | Select-String storeId
$storeid_short = $storeid -replace "storeId: ",""
$alldisks = Mcli-Get disklocator -p siteName=$siteName, storeId=$storeid_short | Select-String diskLocatorName
foreach($disk in $alldisks)
{
$disk1 = $disk | Select-String diskLocatorName
$disklocator_short = $disk1 -replace "diskLocatorName: ",""
foreach($diksloc in $disklocator_short)
{
  
 $VDtests = @{} 
  
 $DiskVersion = Mcli-Get DiskVersion -p diskLocatorName=$disklocator_short, siteName=$siteName, storeName=$storename
$diskreplstatus = $DiskVersion | Select-String goodInventoryStatus
$diskreplstatus_short = $diskreplstatus -replace "goodInventoryStatus: ","" 
  
  
 $disklocator_short
$diskreplstatus_short
  
 # vDiskFileName & createDate 
 $pathA = mcli-get store -p storeName=$storename | Select-String path -casesensitive
$path = $pathA -replace "path: ",""
  
 $diskfilenameA = Mcli-Get DiskVersion -p diskLocatorName=$disklocator_short, siteName=$siteName, storeName=$storename | Select-String diskFileName 
 $diskfilename = $diskfilenameA -replace "diskFileName: ","<br>"
  
 $createDateA = Mcli-Get DiskVersion -p diskLocatorName=$disklocator_short, siteName=$siteName, storeName=$storename | Select-String createDate 
 $createDate = $createDateA -replace "createDate: ","<br>"
  
 $VDtests.vDiskFileName = "OK", " $diskfilename"
Write-Host ("Path is $path $disklocator_short $diskfilename")
  
 $VDtests.createDate = "OK", " $createDate"
Write-Host ("Path is $path $disklocator_short $createDate")
  
 $vdiskResults.$disklocator_short = $VDtests
  
  
  
 #Check if correct replicated
if($diskreplstatus_short -eq 1 ){
"$disklocator_short correct replicated" | LogMe
$VDtests.ReplState = "SUCCESS", "Replication is OK"
  
 } else {
"$disklocator_short not correct replicated " | LogMe -display -error
$VDtests.ReplState = "ERROR", "Replication is NOT OK"
}
 # Check deviceCount: 
 $diskdevicecount = $DiskVersion | Select-String deviceCount
$diskdevicecounts_short = $diskdevicecount -replace "deviceCount: ","<br>" 
 $VDtests.deviceCount = "OK", "$diskdevicecounts_short "
  
  
 #Label Storename 
 $VDtests.Store = "OK", " $storename "
Write-Host ("Store is $storename")
  
 $vdiskResults.$disklocator_short = $VDtests
  
  
# Check for LB-Algorithm
# ----------------------
# Feel free to change it to the the from you desired State (e.g.Exchange a SUCCESS with a WARNING)
# In this default configuration "BestEffort" or "None" is desired and appears green on the output.
# is desired)

#ServeName must be empty! otherwise no LB is active!
$LBnoServer = ""
$LBnoServer_short = ""
$LBnoServer = Mcli-Get disklocator -p siteName=$siteName, storeName=$storename, diskLocatorName=$disklocator_short | Select-String serverName
$LBnoServer_short = $LBnoServer -replace "serverName: ","" 
Write-Host ("vDisk is fix assigned to $LBnoServer")
#not assigned to a server
if ($LBnoServer_short -eq "")
		{
		$LBAlgo = Mcli-Get disklocator -p siteName=$siteName, storeName=$storename | Select-String subnetAffinity
		$LBAlgo_short = $LBAlgo -replace "subnetAffinity: ","" 
		  
		#SubnetAffinity: 1=Best Effort, 2= fixed, 0=none
		if($LBAlgo_short -eq 1 ){
		"LB-Algorythm is set to BestEffort" | LogMe
		$VDtests.LoadBalancingAlgorithm = "SUCCESS", "LB is set to BEST EFFORT"} 
		  
		 elseif($LBAlgo_short -eq 2 ){
		"LB-Algorythm is set to fixed" | LogMe
		$VDtests.LoadBalancingAlgorithm = "WARNING", "LB is set to FIXED"}
		  
		 elseif($LBAlgo_short -eq 0 ){
		"LB-Algorythm is set to none" | LogMe
		$VDtests.LoadBalancingAlgorithm = "SUCCESS", "LB is set to NONE, least busy server is used"}

		}

#Disk fix assigned to a server
else
{
$VDtests.LoadBalancingAlgorithm = "ERROR", "vDisk is fix assigned to $LBnoServer, no LoadBalancing!"}
}
  
  
  
 #Check for WriteCacheType
# -----------------------
# Feel free to change it to the the from you desired State (e.g.Exchange a SUCCESS with a WARNING)
# In this default configuration, only "Cache to Ram with overflow" and "Cache to Device Hard disk" is desired and appears green on the output.
  
 $WriteCacheType = Mcli-Get DiskInfo -p diskLocatorName=$disklocator_short, siteName=$siteName, storeName=$storename
$WriteCacheType_short = $WriteCacheType -replace "WriteCacheType: ",""
  
 #$WriteCacheType 9=RamOfToHD 0=PrivateMode 4=DeviceHD 8=DeviceHDPersistent 3=DeviceRAM 1=PVSServer 7=ServerPersistent 
  
 if($WriteCacheType_short -eq 9 ){
"WC is set to Cache to Device Ram with overflow to HD" | LogMe
$VDtests.WriteCacheType = "SUCCESS", "WC Cache to Ram with overflow to HD"}
  
 elseif($WriteCacheType_short -eq 0 ){
"WC is not set because vDisk is in PrivateMode (R/W)" | LogMe
$VDtests.WriteCacheType = "Error", "vDisk is in PrivateMode (R/W) "}
  
 elseif($WriteCacheType_short -eq 4 ){
"WC is set to Cache to Device Hard Disk" | LogMe
$VDtests.WriteCacheType = "SUCCESS", "WC is set to Cache to Device Hard Disk"}
  
 elseif($WriteCacheType_short -eq 8 ){
"WC is set to Cache to Device Hard Disk Persistent" | LogMe
$VDtests.WriteCacheType = "Error", "WC is set to Cache to Device Hard Disk Persistent"}
  
 elseif($WriteCacheType_short -eq 3 ){
"WC is set to Cache to Device Ram" | LogMe
$VDtests.WriteCacheType = "WARNING", "WC is set to Cache to Device Ram"}
  
 elseif($WriteCacheType_short -eq 1 ){
"WC is set to Cache to PVS Server HD" | LogMe
$VDtests.WriteCacheType = "Error", "WC is set to Cache to PVS Server HD"}
  
 elseif($WriteCacheType_short -eq 7 ){
"WC is set to Cache to PVS Server HD Persistent" | LogMe
$VDtests.WriteCacheType = "Error", "WC is set to Cache to PVS Server HD Persistent"}
}
}
}
}
  

# ======= PVS Server Check ==================================================================
"Check PVS Servers" | LogMe -display -progress
" " | LogMe -display -progress
 
$PVSResults = @{}
$allPVSServer = mcli-get server | Select-String serverName
foreach($PVServerName in $allPVSServer)
{
$PVStests = @{} 
  
 $PVServerName1 = $PVServerName | Select-String serverName
$PVServerName_short = $PVServerName1 -replace "serverName: ","" 
 $PVServerName_short
  
 # Ping server 
 $result = Ping $PVServerName_short 100
if ($result -ne "SUCCESS") { $PVStests.Ping = "ERROR", $result }
else { $PVStests.Ping = "SUCCESS", $result 
 } 
  

#Check PVS Disk status
 try{
 $disks = gwmi -ComputerName $PVServerName_Short win32_logicaldisk | Where-Object {
            ($_.driveType -eq 3) -and (($_.deviceID -eq "C:") -or ($_.deviceID -eq "E:") -or ($_.deviceID -eq "F:"))
            }
        foreach($disk in $disks)
  {
  $deviceID = $disk.DeviceID;
                [float]$size = $disk.Size;
                [float]$freespace = $disk.FreeSpace;
                $percentFree = [Math]::Round(($freespace / $size) * 100, 2);
                $sizeGB = [Math]::Round($size / 1073741824, 2);
                $freeSpaceGB = [Math]::Round($freespace / 1073741824, 2);
  if ($disk.deviceid -eq "C:")
  {
  if ($percentfree -lt $drivespsaceerror)  
  {
  $PVStests.Cdrive = "ERROR", $freespaceGB
  }
  elseif ($percentfree -lt $drivespacewarning)
  {
  $PVStests.Cdrive = "WARNING", $freespaceGB
  }
  else
  {
  $PVStests.Cdrive = "SUCCESS",$freespaceGB
  }
  }
  elseif ($disk.deviceid -eq "E:")
  {
   if ($percentfree -lt $drivespsaceerror)
  {
  $PVStests.Edrive = "ERROR", $freespaceGB
  }
  elseif ($percentfree -lt $drivespacewarning)
  {
  $PVStests.Edrive = "WARNING", $freespaceGB
  }
  else
  {
  $PVStests.Edrive = "SUCCESS",$freespaceGB
  }
  }
  else
  {
   if ($percentfree -lt $drivespsaceerror)
  {
  $PVStests.Fdrive = "ERROR", $freespaceGB
  }
  elseif ($percentfree -lt $drivespacewarning)
  {
  $PVStests.Fdrive = "WARNING", $freespaceGB
  }
  else
  {
  $PVStests.Fdrive = "SUCCESS",$freespaceGB
  }
  }
  }
  }
  catch [Exception]{
                        Write-Host $PVServerName_Short  $_.exception.message
                        -join ($PVServerName_Short,  $_.exception.message) | logme
                     }
  
 #Check PVS Service Status
$serverstatus = mcli-get ServerStatus -p serverName=$PVServerName_short -f status
$actviestatus = $serverstatus[4].TrimStart("status: ") -as [int]
if ($actviestatus -eq 1) { $PVStests.Active = "SUCCESS", "active" }
else { $PVStests.Active = "Error","inactive" }

# Check services
		if ((Get-Service -Name "soapserver" -ComputerName $PVServerName_short).Status -Match "Running") {
			"SoapService running..." | LogMe
			$PVStests.SoapService = "SUCCESS", "Success"
		} else {
			"SoapService service stopped"  | LogMe -display -error
			$PVStests.SoapService = "ERROR", "Error"
		}
			
		if ((Get-Service -Name "StreamService" -ComputerName $PVServerName_short).Status -Match "Running") {
			"StreamService service running..." | LogMe
			$PVStests.StreamService = "SUCCESS","Success"
		} else {
			"StreamService service stopped"  | LogMe -display -error
			$PVStests.StreamService = "ERROR","Error"
		}
			
		if ((Get-Service -Name "BNTFTP" -ComputerName $PVServerName_short).Status -Match "Running") {
			"TFTP service running..." | LogMe
			$PVStests.TFTPService = "SUCCESS","Success"
		} else {
			"TFTP  service stopped"  | LogMe -display -error
			$PVStests.TFTPService = "ERROR","Error"
		
 }
  
 #Check PVS deviceCount
$serverdevicecount = mcli-get ServerStatus -p serverName=$PVServerName_short -f deviceCount
$numberofdevices = $serverdevicecount[4].TrimStart("deviceCount: ") -as [int]
if ($numberofdevices -gt 1) { $PVStests.deviceCount = "SUCCESS", " $numberofdevices active" }
else { $PVStests.deviceCount = "WARNING","No devices on this server" }
  
  
  
 $PVSResults.$PVServerName_short = $PVStests
  
}
# ======= PVS Farm Check ====================================================================
"Read some PVS Farm Parameters" | LogMe -display -progress
" " | LogMe -display -progress
$PVSFarmResults = @{}
$PVSfarms = mcli-get Farm #| Select-String FarmName

$farmname = mcli-get Farm | Select-String FarmName
$farmname_short = $farmname -replace "farmName: ",""

$Nr=0
foreach($PVSFarm in $PVSfarms)
{
$PVSFarmtests = @{}
# remove not needed record parts
if ($PVSFarm -like '*description*'){continue;}
if ($PVSFarm -like '*record*'){continue;}
if ($PVSFarm -like '*failover*'){continue;}
if ($PVSFarm -like '*executing*'){continue;}
if ($PVSFarm -like '*defaultSiteName*'){continue;}
if ($PVSFarm -like '*autoAddEnabled*'){continue;}
if ($PVSFarm -like '*role*'){continue;}
if ($PVSFarm -like '*audit*'){continue;}
if ($PVSFarm -like '*defaultSiteId*'){continue;}
if ($PVSFarm -like '*maxVersions*'){continue;}
if ($PVSFarm -like '*databaseInstanceName*'){continue;}
if ($PVSFarm -like '*farmId*'){continue;}
if ($PVSFarm -like '*merge*'){continue;}
if ($PVSFarm -like '*adGroups*'){continue;}
 if ($PVSFarm -ne '') {
$Nr += 1
$arr = $PVSFarm -split ': '
$farmsetting = $arr[0]
$PVSFarmtests.Setting = "NEUTRAL", "$farmsetting"
$arr = $PVSFarm -split ': '
$farmsettingvalue = $arr[1]
$PVSFarmtests.Value = "NEUTRAL", "$farmsettingvalue"
$farmnr=$Nr
$PVSFarmResults.$farmnr = $PVSFarmtests
}
}
 
 
 
# ======= Write all results to an html file =================================================
#need to get today and then yesterday date in format yyyy/mm/dd in order to run auditTrail
$longStartDate = $today.AddDays(-$auditRetrievalDays)

$shortStartDate = convertDate($longStartDate)
$shortEndDate = convertDate($today)

# this line retrieves the PVs audit info for the last 1 day, it is returned as an ONE array of strings for the full farm.
$auditTrail = mcli-get auditTrail -p beginDate=$shortStartDate,endDate=$shortEndDate
getAuditTrail($auditTrail)
Write-Host ("Saving results to html report: " + $resultsHTM)
writeHtmlHeader "PVS Farm Report $farmname_short" $resultsHTM
writeTableHeader $resultsHTM $TargetFirstheaderName $TargetheaderNames $TargetheaderWidths $TargetTablewidth
$allResults | sort-object -property collectionName | % { writeData $allResults $resultsHTM $TargetheaderNames}
writeTableFooter $resultsHTM
writeTableHeader $resultsHTM $vDiksFirstheaderName $vDiskheaderNames $vDiskheaderWidths $vDisktablewidth
$vdiskResults | sort-object -property ReplState | % { writeData $vdiskResults $resultsHTM $vDiskheaderNames }
writeTableFooter $resultsHTM
writeTableHeader $resultsHTM $PVSFirstheaderName $PVSheaderNames $PVSheaderWidths $PVStablewidth
$PVSResults | sort-object -property PVServerName_short | % { writeData $PVSResults $resultsHTM $PVSheaderNames}
writeTableFooter $resultsHTM
 
writeTableHeader $resultsHTM $PVSFirstFarmheaderName $PVSFarmHeaderNames $PVSFarmWidths $PVSFarmTablewidth
$PVSFarmResults | % { writeData $PVSFarmResults $resultsHTM $PVSFarmHeaderNames}

writeHtmlAuditFooter $resultsHTM
writeAuditTableHeader $resultsHTM
#writeAuditData $ALLauditTrailHashTable $resultsHTM 
$ALLauditTrailHashTable.keys | sort-object $_ -Descending | ForEach-Object { writeAuditData $ALLauditTrailHashTable.item($_) $resultsHTM}
writeTableFooter $resultsHTM
writeHtmlFooter $resultsHTM
#send email
$emailSubject = ("$emailSubjectStart - $farmname_short - " + (Get-Date -format R))
$mailMessageParameters = @{
From = $emailFrom
To = $emailTo
Subject = $emailSubject
SmtpServer = $smtpServer
Body = (gc $resultsHTM) | Out-String
Attachment = $resultsHTM
}
# Send mail if you wish
#Send-MailMessage @mailMessageParameters -BodyAsHtml -Priority $mailprio

copy $resultsHTM $resultsNowHTM

#clear out old files
$retentionPeriod = New-TimeSpan -day $retentionDays

$fileList = get-childitem -path $saveToFarm *.htm

foreach ($file in $fileList){
    #$file
    $datePrefix = $null
    $erroractionPreference = 'silentlyContinue'
    $datePrefix = [dateTime]$file.BaseName.substring(0,9)
    $erroractionPreference = 'continue'
    #$dateprefix
    if ($dateprefix -ne $null){
       #$file
       $delDay = $datePrefix + $retentionPeriod
       if ($delDay -le $today ){
          #"Delete it"
          $file | Remove-Item
        }
     }
}

Function writeHtmlAuditFooter
{
param($fileName)
@"
</table>
<table width='1245'>
<tr bgcolor='#CCCCCC'>
<td colspan='7' height='25' align='left'>
<font face='courier' color='#003399' size='2'><strong>Audited configuration changes performed over the last $auditRetrievalDays days</strong></font>
</td>
</tr>
</table>
</body>
</html>
"@ | Out-File $FileName -append
}
Function writeAuditTableHeader
{
param($fileName)
$auditTableHeader = @"
<table width='1245'><tbody>
<tr bgcolor=#CCCCCC>
"@

$i = 0
while ($i -lt $auditHeaderNames.count) {
	$auditHeaderName = $auditHeaderNames[$i]
	$auditHeaderWidth = $auditHeaderWidths[$i]
	$audittableHeader += "<td width='" + $auditHeaderWidth + "%' align='center'><strong>$auditHeaderName</strong></td>"
	$i++
}

$audittableHeader += "</tr>"

$audittableHeader | Out-File $fileName -append
}

# ==============================================================================================

Function writeAuditData
{
	param($auditData, $fileName)
    
    # $auditData

    if ($auditData.category.contains("RED")){
        $bgcolor = "#FF0000"; $fontColor = "#FFFFFF"
        #"RED"
        }
    elseif ($auditData.category.contains("AMBER")){
        $bgcolor = "#FF7700"; $fontColor = "#FFFFFF"
        #"AMBER"
        }
     elseif ($auditData.category.contains("GREEN")){
        $bgcolor = "#387C44"; $fontColor = "#FFFFFF"
        #"GREEN"
        }

	$auditTableEntry += "<tr>"
	$tableEntry += ("<td bgcolor='#CCCCCC' align=center><font color='#003399'>$recordNumber</font></td>")
	$auditHeaderNames | foreach {
        #"RED"
        #$_
        #"BLUE"
        if ($_.contains("Action")){
           $cellBgcolor = $bgcolor
           $cellFontColor = $FontColor
            }
        else {
            $cellBgcolor = "#CCCCCC"
            $cellFontColor = "#003399"
        }
        
		$auditTestResult = $auditData.$_	
    	$auditTableEntry += ("<td bgcolor='" + $cellBgcolor + "' align=center><font color='" + $cellFontColor + "'>$auditTestResult</font></td>")
		}
		
	$auditTableEntry += "</tr>"
	$auditTableEntry | Out-File $fileName -append

    # pause
   
}
