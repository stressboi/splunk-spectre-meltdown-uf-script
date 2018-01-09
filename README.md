# splunk-spectre-meltdown-uf-script
A script modified from speed47's work to provide KV-pair results into a Splunk UF scripted input

Original can be found here: https://github.com/speed47/spectre-meltdown-checker.

I added a date/time string to the output, processor details, arch details, and then stripped out the spaces and color codes in the output so that Splunk parses the information more elegantly.

Put this somewhere that it can execute within the bin directory of an app. It should execute as root for accurate results, so you may want to setuid it or something.

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
