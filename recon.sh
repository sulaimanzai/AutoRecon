#!/bin/bash

## VARIABLES
ToolsDIR="/root/Recon/Tools"
ResultsPath="/root/Recon"
TransferSH="https://transfer.sh"
subjackDebug="/root/go/src/github.com/haccer/subjack/fingerprints.json"

## FUNCTION
die() {
    printf '%s\n' "$1" >&2
    exit 1
}

help() {
  banner
  echo -e "Usage : ./recon.sh -d domain.tld -a -u
      -d | --domain  (required) : Launch passive scan (Passive Amass, CRT.sh, Certspotter, Subfinder, Subjack, TkoSubs, CORStest)
      -a | --active  (optional) : Launch active scans (Active Amass, Sublist3r, GoWitness, CORStest)
      -m | --masscan (optional) : Launch masscan (Can be very long & very aggressive ...)
      -s | --screen  (optional) : Take screenshots with GoWitness (can be very long)
      -u | --upload  (optional) : Upload archive on Transfer.sh
  "
}

banner() {
  echo -e "
                _        _____                      
     /\        | |      |  __ \                     
    /  \  _   _| |_ ___ | |__) |___  ___ ___  _ __  
   / /\ \| | | | __/ _ \|  _  // _ \/ __/ _ \| '_ \ 
  / ____ \ |_| | || (_) | | \ \  __/ (_| (_) | | | |
 /_/    \_\__,_|\__\___/|_|  \_\___|\___\___/|_| |_|
 "
}

scan() {
  banner
  echo -e "Scan is in \e[31mprogress\e[0m, take a coffee"

  ## ENUM SUB-DOMAINS
  echo -e ">> Passive subdomains enumeration with \e[36mAmass\e[0m, \e[36mCertspotter\e[0m, \e[36mSubfinder\e[0m & \e[36mCrt.sh\e[0m"

  # LAUNCH AMASS (PASSIVE)
  $ToolsDIR/Amass/amass enum -passive -d $domain -o $ResultsPath/$domain/passive.txt > /dev/null 2>&1

  ## ASK DOMAINS FROM CRT.SH & CERTSPOTTER
  curl -s https://certspotter.com/api/v0/certs\?domain\=$domain | jq '.[].dns_names[]' | sed 's/\"//g' | sed 's/\*\.//g' | sort | uniq >> $ResultsPath/$domain/certspotter.txt
  curl -s "https://crt.sh/?q=%.$domain&output=json" | jq '.[].name_value' | sed 's/\"//g' | sed 's/\*\.//g' | sort | uniq >> $ResultsPath/$domain/crtsh.txt

  ## LAUNCH SUBFINDER
  $ToolsDIR/Subfinder -d $domain -o $ResultsPath/$domain/subfinder.txt > /dev/null 2>&1

  if [ -v active ] ## IF ACTIVE OPTION WAS PROVIDE
  then
    ## LAUNCH AMASS (ACTIVE) & SUBLIST3R ACTIVE SCAN
    echo -e ">> Active subdomains enumeration with \e[36mAmass\e[0m & \e[36mSublist3r\e[0m"
    $ToolsDIR/Amass/amass enum -active -brute -min-for-recursive 1 -d $domain -o $ResultsPath/$domain/active.txt -p 80,443 -w $ToolsDIR/Amass/wordlists/subdomains-top1mil-110000.txt > /dev/null 2>&1
    python3 $ToolsDIR/Sublist3r/sublist3r.py -d $domain -o $ResultsPath/$domain/sublist3r.txt > /dev/null 2>&1
  fi

  ## COMBINE RESULTS OF AMASS, SUBLIST3R, CRTSH AND CERTSPOTTER
  cat $ResultsPath/$domain/passive.txt $ResultsPath/$domain/certspotter.txt $ResultsPath/$domain/crtsh.txt $ResultsPath/$domain/subfinder.txt > $ResultsPath/$domain/$domain.txt
  rm $ResultsPath/$domain/passive.txt $ResultsPath/$domain/certspotter.txt $ResultsPath/$domain/crtsh.txt
  if [ -v active ] ## IF ACTIVE OPTION WAS PROVIDE
  then
    cat $ResultsPath/$domain/active.txt $ResultsPath/$domain/sublist3r.txt >> $ResultsPath/$domain/$domain.txt
    rm $ResultsPath/$domain/active.txt $ResultsPath/$domain/sublist3r.txt
  fi

  ## SORTS AND REMOVES DUPLICATES
  sort $ResultsPath/$domain/$domain.txt | uniq > $ResultsPath/$domain/domains.txt
  rm $ResultsPath/$domain/$domain.txt

  ## CHECK RESULTS WITH MASSDNS
  echo -e ">> Check results with \e[36mMassDNS\e[0m"
  printf "8.8.8.8\n1.1.1.1" > $ToolsDIR/MassDNS/resolvers.txt
  $ToolsDIR/MassDNS/bin/massdns -r $ToolsDIR/MassDNS/resolvers.txt -t A -o S -w $ResultsPath/$domain/massdns.txt $ResultsPath/$domain/domains.txt > /dev/null 2>&1
  rm $ResultsPath/$domain/domains.txt

  ## CLEAN MASSDNS RESULTS
  grep -Po "([A-Za-z0-9]).*$domain" $ResultsPath/$domain/massdns.txt > $ResultsPath/$domain/tmp_domains.txt
  sed 's/\..CNAME.*/ /g' $ResultsPath/$domain/tmp_domains.txt > $ResultsPath/$domain/tmp2_domains.txt
  sed 's/CNAME.*/ /g' $ResultsPath/$domain/tmp2_domains.txt | sort | uniq > $ResultsPath/$domain/domains.txt
  rm $ResultsPath/$domain/tmp_domains.txt $ResultsPath/$domain/tmp2_domains.txt

  ## CHECK TAKEOVER WITH SUBJACK AND TKOSUBS
  echo -e ">> Checking takeover with \e[36mSubjack\e[0m & \e[36mTkoSubs\e[0m"
  $ToolsDIR/Subjack -w $ResultsPath/$domain/domains.txt -t 100 -o $ResultsPath/$domain/Subjack.txt -c $subjackDebug -v -ssl > /dev/null 2>&1
  $ToolsDIR/TkoSubs/TkoSubs -domains=$ResultsPath/$domain/domains.txt -data=$ToolsDIR/TkoSubs/providers-data.csv -output=$ResultsPath/$domain/TkoSubs.csv > /dev/null 2>&1

  if [ -v active ] ## IF ACTIVE OPTION WAS PROVIDE
  then
    ## CREATE  FILES WITH COMPLETE URL FOR LINKFINDER AND GoWitness
    sed -e 's/^/https:\/\//' $ResultsPath/$domain/domains.txt > $ResultsPath/$domain/urlsHTTPS.txt
    sed -e 's/^/http:\/\//' $ResultsPath/$domain/domains.txt > $ResultsPath/$domain/urlsHTTP.txt
    sed -i s/' '\$//g $ResultsPath/$domain/urlsHTTPS.txt
    sed -i s/' '\$//g $ResultsPath/$domain/urlsHTTP.txt

    ## GET IP OF EACH DOMAINS
    cat $ResultsPath/$domain/domains.txt | while read rline; do host $rline | grep " has address "|cut -d" " -f4 >> $ResultsPath/$domain/IP.txt
    done
    cat $ResultsPath/$domain/IP.txt | sort | uniq > $ResultsPath/$domain/IPs.txt
    rm $ResultsPath/$domain/IP.txt
  fi

  if [ -v screen ] ## IF ACTIVE OPTION WAS PROVIDE
  then
        ## SCREENSHOT WITH GOWITNESS
    echo -e ">> Screenshot with \e[36mGoWitness\e[0m"
    mkdir -p $ResultsPath/$domain/Screenshots/HTTP
    mkdir -p $ResultsPath/$domain/Screenshots/HTTPS
    $ToolsDIR/GoWitness file --source=$ResultsPath/$domain/urlsHTTP.txt --destination "$ResultsPath/$domain/Screenshots/HTTP" > /dev/null 2>&1
    $ToolsDIR/GoWitness file --source=$ResultsPath/$domain/urlsHTTPS.txt --destination "$ResultsPath/$domain/Screenshots/HTTPS" > /dev/null 2>&1
  fi

    ## CHECKING FOR CORS MISCONFIGURATION
    echo -e ">> Checking CORS misconfiguration with \e[36mCORSTest\e[0m"
    python2 $ToolsDIR/CORStest/corstest.py -q $ResultsPath/$domain/domains.txt -v >> $ResultsPath/$domain/CORS.txt

    ## LAUNCH MASSCAN
    if [ -v masscan ]
    then
      echo -e ">> Checking open ports with \e[36mMasscan\e[0m"
      masscan -p1-65535 -iL $ResultsPath/$domain/IPs.txt --rate=1000 -oJ $ResultsPath/$domain/masscan.json > /dev/null 2>&1
    fi

    ## DIRECTORY CLEANING
    rm $ResultsPath/$domain/urlsHTTP.txt $ResultsPath/$domain/urlsHTTPS.txt 

  ## DIRECTORY CLEANING
  rm $ResultsPath/$domain/massdns.txt

  ## CREATE AN ARCHIVE
  tar czvf $ResultsPath/$domain/$domain.tar.gz $ResultsPath/$domain/* > /dev/null 2>&1

  echo -e "\n=========== Scan is \e[32mfinish\e[0m ==========="
  echo -e "Archive of scan was create, path : \e[36m$ResultsPath/$domain/$domain.tar.gz\e[0m"

  if [ -v upload ] ## IF UPLOAD OPTION WAS PROVIDE
  then
    link=$(curl -H "Max-Downloads: 1" -H "Max-Days: 1" --upload-file $ResultsPath/$domain/$domain.tar.gz $TransferSH/$domain.tar.gz 2>&1 | grep "$TransferSH/.*$domain.tar.gz" -o)
    rm $ResultsPath/$domain/$domain.tar.gz
    echo -e "Download link of your report : \e[36m$link\e[0m"
  fi

   echo -e "======================================\n"
}

while :; do
    case $1 in
        -h|-\?|--help)
            help
            exit
            ;;
        -d|--domain)
            if [ "$2" ]; then
                domain=$2
                shift
            else
                die 'ERROR: "--domain" requires a non-empty option argument.'
            fi
            ;;
        --domain=)
            die 'ERROR: "--domain" requires a non-empty option argument.'
            ;;
        -a|--active)
            active=true
            ;;
        -m|--masscan)
            masscan=true
            ;;
        -s|--screen)
            screen=true
            ;;
        -u|--upload)
            upload=true
            ;;
        --)
            shift
            break
            ;;
        -?*)
            printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
            ;;
        *)
            break
    esac

    shift
done

if [ -z "$domain" ]
then
  help
  die 'ERROR: "--domain" requires a non-empty option argument.'
else
  if [ ! -d "$ResultsPath/$domain" ];then
    mkdir $ResultsPath/$domain
  else
    while true; do
        echo -e "The dir \e[36m$ResultsPath/$domain\e[0m already exists, delete ? [y/n]"
        read -p ">> " yn
        case $yn in
            [Yy]* ) rm -r $ResultsPath/$domain; mkdir $ResultsPath/$domain; break;;
            [Nn]* ) break;;
            * ) echo "Please answer y or n.";;
        esac
    done
  fi
  scan
fi
