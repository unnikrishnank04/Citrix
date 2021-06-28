#Set $mclipath based on your environment usually located under C:\Program Files\Citrix\Provisioning Services
# or Run the script from the folder: "C:\Program Files\Citrix\Provisioning Services" without doing any changes
# Once the script runs it creates a log file in the same location as the script resides in named "Personalitysetlogs.txt" for your reference
# Create the personality.csv with the column headers: Devicename, IP, DNS1, DNS2, Gateway in the order mentioned here and place it wherever
# If the personality.csv is not in the same folder as the script be sure to edit the $filepath to the correct location



#Parameters set
$mclipath = "E:\vendor_apps\Citrix\Provisioning Services\mcli.exe"
$filepath = ".\personality.csv"

#Import the CSV file
Import-CSV $filepath -Header Devicename,IP,DNS1,DNS2,DNS3,Gateway| Foreach-Object{
   Write-Host "Current Device Name:" $_.Devicename
   Write-Host "IP" $_.IP
   Write-Host "DNS1" $_.DNS1
   Write-Host "DNS2" $_.DNS2
   Write-Host "DNS3" $_.DNS3
   Write-Host "Gateway" $_.Gateway

   #Start Setup 
   if ($_.Devicename -eq "DeviceName")
   {
   }
   else
   {
   $ps = new-object System.Diagnostics.Process
   $ps.StartInfo.Filename = $mclipath
   $ps.StartInfo.Arguments = "setlist devicepersonality -p deviceName=" +$_.Devicename+" -r name=IP value=" +$_.IP+" name=DNS1 value=" +$_.DNS1+" name=DNS2 value=" +$_.DNS2+" name=DNS3 value="+$_.DNS3+ " name=Gateway value="+$_.Gateway
   $ps.StartInfo.RedirectStandardOutput = $True
   $ps.StartInfo.UseShellExecute = $false
   $ps.start()
   $ps.WaitForExit()
   [string] $Out = $ps.StandardOutput.ReadToEnd(); 
   
   "Current Device Name:"+  $_.Devicename >> .\personalitysetlogs.txt
   "IP: "+  $_.IP >> .\personalitysetlogs.txt
   "DNS1: "+  $_.DNS1 >> .\personalitysetlogs.txt
   "DNS2: "+  $_.DNS2 >> .\personalitysetlogs.txt
   "DNS3: "+  $_.DNS3 >> .\personalitysetlogs.txt
   "Gateway: "+  $_.Gateway >> .\personalitysetlogs.txt
   $out >> .\personalitysetlogs.txt
   }
}