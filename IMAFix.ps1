$servers = Get-Content .\servers.txt
$numberofthreads = 60 
$fixima = {
param ($server)

if (Test-Connection $server -count 2)
{
try
{
Invoke-Command -ComputerName $server -command {taskkill /IM imasrv.exe /F | dsmaint recreatelhc | net start imaservice}
$statement = "server fixed" + $server
$statement >> c:\result.txt
}
catch
{
$statement = "$server fix is not working"
$statement >> c:\result.txt 
}
}
else
{
$statement = "$server is unreachable"
$statement >> c:\result.txt
}
}

get-job | Remove-Job
foreach($server in $servers)
{

while ((get-job -State Running).count -gt $numberofthreads)
{
write-host (get-job -state Running ).count " is the total running job count "
write-host "entering Sleep mode, and waiting for some job to complete"
start-sleep -Seconds 20

}
   write-host "working on $server "
   Start-Job -scriptblock $fixima -ArgumentList $server -Name $server | out-Null
}
 
write-host "All Jobs are scheduled, waiting for them to complete"  

$Index = 0 
while((((get-job -State "running").count) -gt 0))
{
$index = $index + 1
get-job -State "running" | select name, psbegintime,psendtime,state > ".\jobstatus.txt"
write-host "sleeping for few mins"
start-sleep 10
}

Get-Job | Wait-Job -Timeout 300 | Out-Null 


write-host "Check the results at  results.txt"