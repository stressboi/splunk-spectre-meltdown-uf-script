# splunk-spectre-meltdown-uf-script
A script modified from speed47's work to provide KV-pair results into Splunk, via a Universal Forwarder-driven scripted input. This is likely to only work on Linux hosts!

Original can be found here: https://github.com/speed47/spectre-meltdown-checker.

I added a date/time string to the output, processor details, arch details, and then stripped out the spaces and color codes in the output so that Splunk parses the information more elegantly.

Put this somewhere that it can execute within the bin directory of an app. According to the original author, it should execute as root for accurate results, so you may want to setuid it or something. That said, you're gonna have a bad time if someone wants to be evil with this, or if you deploy this via deployment server, which would make it easier to be evil. Therefore...

In limited testing I have seen it execute just fine as something other than root, so if your UF is running as lesser privs, you should be OK.

```
[script://./bin/meltdown-spectre-check.sh]
interval = 3600
sourcetype = meltdown_spectre_checker
source = meltdown-spectre-check.sh
index = main
disabled = 0
```

Example search, assuming data goes into "main" index:

```
index=main sourcetype=meltdown_spectre_checker
| stats values(Target_UNAME) as uname, values(Found_IPADDRESS) as "IP Address" values(Found_PROC) as "Processor" values(CVE_2017_5715_STATUS) as "CVE-2017-5715 Spectre 1" values(CVE_2017_2753_STATUS) as "CVE-2017-2753 Spectre 2" values(CVE_2017_5754_STATUS) as "CVE-2017-5754 Meltdown" by host
```

brodsky@splunk.com
