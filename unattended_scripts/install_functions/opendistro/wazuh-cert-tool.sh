#!/bin/bash

# Program to generate the certificates necessary for Wazuh installation
# Copyright (C) 2015-2021, Wazuh Inc.
#
# This program is a free software; you can redistribute it
# and/or modify it under the terms of the GNU General Public
# License (version 2) as published by the FSF - Free Software
# Foundation.

debug=''
elasticinstances="elasticsearch-nodes:"
filebeatinstances="wazuh-servers:"
kibanainstances="kibana:"
elastichead='# Elasticsearch nodes'
filebeathead='# Wazuh server nodes'
kibanahead='# Kibana node'

## Prints information
logger() {

    now=$(date +'%m/%d/%Y %H:%M:%S')
    case $1 in 
        "-e")
            mtype="ERROR:"
            message="$2"
            ;;
        "-w")
            mtype="WARNING:"
            message="$2"
            ;;
        *)
            mtype="INFO:"
            message="$1"
            ;;
    esac
    echo $now $mtype $message
}

readInstances() {

    if [ -f ${base_path}/instances.yml ]; then
        logger "Configuration file found. Creating certificates..."
        eval "mkdir ${base_path}/certs $debug"
    else
        logger -e "No configuration file found."
        exit 1;
    fi

    readFile

}

getHelp() {
    echo ""
    echo "Usage: $0 options"
    echo -e "        -a,  --admin-certificates"
    echo -e "                Creates the admin certificates."
    echo -e "        -ca, --root-ca-certificates"
    echo -e "                Creates the root-ca certificates."
    echo -e "        -e,  --elasticsearch-certificates"
    echo -e "                Creates the Elasticsearch certificates."
    echo -e "        -w,  --wazuh-certificates"
    echo -e "                Creates the Wazuh server certificates."
    echo -e "        -k,  --kibana-certificates"
    echo -e "                Creates the Kibana certificates."
    echo -e "        -d,  --debug"
    echo -e "                Enables verbose mode."
    exit 1 # Exit script after printing help    
}

readFile() {

    IFS=$'\r\n' GLOBIGNORE='*' command eval  'instances=($(cat ${base_path}/instances.yml))'
    for i in "${!instances[@]}"; do
    if [[ "${instances[$i]}" == "${elasticinstances}" ]]; then
        elasticlimitt=${i}
    fi
        if [[ "${instances[$i]}" == "${filebeatinstances}" ]]; then
        elasticlimib=${i}
    fi

    if [[ "${instances[$i]}" == "${filebeatinstances}" ]]; then
        filebeatlimitt=${i}
    fi
    
    if [[ "${instances[$i]}" == "${kibanainstances}" ]]; then
        filebeatlimib=${i}
    fi  
    done

    ## Read Elasticsearch nodes
    counter=${elasticlimitt}
    i=0
    while [ "${counter}" -le "${elasticlimib}" ]
    do
        if  [ "${instances[counter]}" !=  "${elasticinstances}" ] && [ "${instances[counter]}" !=  "${filebeatinstances}" ] && [ "${instances[counter]}" !=  "${filebeathead}" ] && [ "${instances[counter]}" !=  "    ip:" ] && [ -n "${instances[counter]}" ]; then
            elasticnodes[i]+="$(echo "${instances[counter]}" | tr -d '\011\012\013\014\015\040')"
            ((i++))
        fi    

        ((counter++))
    done

    ## Read Filebeat nodes
    counter=${filebeatlimitt}
    i=0
    while [ "${counter}" -le "${filebeatlimib}" ]
    do
        if  [ "${instances[counter]}" !=  "${filebeatinstances}" ] && [ "${instances[counter]}" !=  "${kibanainstances}" ] && [ "${instances[counter]}" !=  "${kibanahead}" ] && [ "${instances[counter]}" !=  "    ip:" ] && [ -n "${instances[counter]}" ]; then
            filebeatnodes[i]+="$(echo "${instances[counter]}" | tr -d '\011\012\013\014\015\040')"
            ((i++))
        fi    

        ((counter++))
    done

    ## Read Kibana nodes
    counter=${filebeatlimib}
    i=0
    while [ "${counter}" -le "${#instances[@]}" ]
    do
        if  [ "${instances[counter]}" !=  "${kibanainstances}" ]  && [ "${instances[counter]}" !=  "${kibanahead}" ] && [ "${instances[counter]}" !=  "    ip:" ] && [ -n "${instances[counter]}" ]; then
            kibananodes[i]+="$(echo "${instances[counter]}" | tr -d '\011\012\013\014\015\040')"
            ((i++))
        fi    

        ((counter++))    
    done

}


generateCertificateconfiguration() {

    cat > ${base_path}/certs/${cname}.conf <<- EOF
        [ req ]
        prompt = no
        default_bits = 2048
        default_md = sha256
        distinguished_name = req_distinguished_name
        x509_extensions = v3_req
        
        [req_distinguished_name]
        C = US
        L = California
        O = Wazuh
        OU = Docu
        CN = cname
        
        [ v3_req ]
        authorityKeyIdentifier=keyid,issuer
        basicConstraints = CA:FALSE
        keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
        subjectAltName = @alt_names
        
        [alt_names]
        IP.1 = cip
	EOF

    conf="$(awk '{sub("CN = cname", "CN = '${cname}'")}1' ${base_path}/certs/$cname.conf)"
    echo "${conf}" > ${base_path}/certs/$cname.conf    

    isIP=$(echo "${cip}" | grep -P "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$")
    isDNS=$(echo ${cip} | grep -P "^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9](?:\.[a-zA-Z]{2,})+$" )

    if [[ -n "${isIP}" ]]; then
        conf="$(awk '{sub("IP.1 = cip", "IP.1 = '${cip}'")}1' ${base_path}/certs/$cname.conf)"
        echo "${conf}" > ${base_path}/certs/$cname.conf    
    elif [[ -n "${isDNS}" ]]; then
        conf="$(awk '{sub("CN = cname", "CN =  '${cip}'")}1' ${base_path}/certs/$cname.conf)"
        echo "${conf}" > ${base_path}/certs/$cname.conf     
        conf="$(awk '{sub("IP.1 = cip", "DNS.1 = '${cip}'")}1' ${base_path}/certs/$cname.conf)"
        echo "${conf}" > ${base_path}/certs/$cname.conf 
    else
        logger -e "The given information does not match with an IP or a DNS"  
        exit 1; 
    fi   

}

generateRootCAcertificate() {

    eval "openssl req -x509 -new -nodes -newkey rsa:2048 -keyout ${base_path}/certs/root-ca.key -out ${base_path}/certs/root-ca.pem -batch -subj '/OU=Docu/O=Wazuh/L=California/' -days 3650 ${debug}"

}

generateAdmincertificate() {
    
    eval "openssl genrsa -out ${base_path}/certs/admin-key-temp.pem 2048 ${debug}"
    eval "openssl pkcs8 -inform PEM -outform PEM -in ${base_path}/certs/admin-key-temp.pem -topk8 -nocrypt -v1 PBE-SHA1-3DES -out ${base_path}/certs/admin-key.pem ${debug}"
    eval "openssl req -new -key ${base_path}/certs/admin-key.pem -out ${base_path}/certs/admin.csr -batch -subj '/C=US/L=California/O=Wazuh/OU=Docu/CN=admin' ${debug}"
    eval "openssl x509 -req -in ${base_path}/certs/admin.csr -CA ${base_path}/certs/root-ca.pem -CAkey ${base_path}/certs/root-ca.key -CAcreateserial -sha256 -out ${base_path}/certs/admin.pem ${debug}"

}

generateElasticsearchcertificates() {

    logger "Creating the Elasticsearch certificates..."

    i=0
    while [ ${i} -lt ${#elasticnodes[@]} ]; do
        cname=${elasticnodes[i]}
        cip=${elasticnodes[i+1]}
        rname="-name:"
        cname="${cname//$rname}"
        rip="-"
        cip="${cip//$rip}"
        cname=$(echo ${cname} | xargs)
        cip=$(echo ${cip} | xargs)

        generateCertificateconfiguration cname cip
        eval "openssl req -new -nodes -newkey rsa:2048 -keyout ${base_path}/certs/${cname}-key.pem -out ${base_path}/certs/${cname}.csr -config ${base_path}/certs/${cname}.conf -days 3650 ${debug}"
        eval "openssl x509 -req -in ${base_path}/certs/${cname}.csr -CA ${base_path}/certs/root-ca.pem -CAkey ${base_path}/certs/root-ca.key -CAcreateserial -out ${base_path}/certs/${cname}.pem -extfile ${base_path}/certs/${cname}.conf -extensions v3_req -days 3650 ${debug}"
        eval "chmod 444 ${base_path}/certs/${cname}-key.pem ${debug}"    
        i=$(( ${i} + 2 ))
    done

}

generateFilebeatcertificates() {

    logger "Creating Wazuh server certificates..."

    i=0
    while [ ${i} -lt ${#filebeatnodes[@]} ]; do
        cname=${filebeatnodes[i]}
        cip=${filebeatnodes[i+1]}
        rname="-name:"
        cname="${cname//$rname}"
        rip="-"
        cip="${cip//$rip}"
        cname=$(echo ${cname} | xargs)
        cip=$(echo ${cip} | xargs)

        generateCertificateconfiguration cname cip
        eval "openssl req -new -nodes -newkey rsa:2048 -keyout ${base_path}/certs/${cname}-key.pem -out ${base_path}/certs/${cname}.csr -config ${base_path}/certs/${cname}.conf -days 3650 ${debug}"
        eval "openssl x509 -req -in ${base_path}/certs/${cname}.csr -CA ${base_path}/certs/root-ca.pem -CAkey ${base_path}/certs/root-ca.key -CAcreateserial -out ${base_path}/certs/${cname}.pem -extfile ${base_path}/certs/${cname}.conf -extensions v3_req -days 3650 ${debug}"
        i=$(( ${i} + 2 ))
    done      

}

generateKibanacertificates() {

    logger "Creating Kibana certificate..."

    i=0
    while [ ${i} -lt ${#kibananodes[@]} ]; do
        cname=${kibananodes[i]}
        cip=${kibananodes[i+1]}
        rname="-name:"
        cname="${cname//$rname}"
        rip="-"
        cip="${cip//$rip}"
        cname=$(echo ${cname} | xargs)
        cip=$(echo ${cip} | xargs)

        generateCertificateconfiguration cname cip
        eval "openssl req -new -nodes -newkey rsa:2048 -keyout ${base_path}/certs/${cname}-key.pem -out ${base_path}/certs/${cname}.csr -config ${base_path}/certs/${cname}.conf -days 3650 ${debug}"
        eval "openssl x509 -req -in ${base_path}/certs/${cname}.csr -CA ${base_path}/certs/root-ca.pem -CAkey ${base_path}/certs/root-ca.key -CAcreateserial -out ${base_path}/certs/${cname}.pem -extfile ${base_path}/certs/${cname}.conf -extensions v3_req -days 3650 ${debug}"
        i=$(( ${i} + 2 ))
    done 

}

cleanFiles() {

    eval "rm -rf ${base_path}/certs/*.csr ${debug}"
    eval "rm -rf ${base_path}/certs/*.srl ${debug}"
    eval "rm -rf ${base_path}/certs/*.conf ${debug}"
    eval "rm -rf ${base_path}/certs/admin-key-temp.pem ${debug}"
    logger "Certificates creation finished. They can be found in ${base_path}/certs."

}

main() {

    if [ "$EUID" -ne 0 ]; then
        logger -e "This script must be run as root."
        exit 1;
    fi    

    if [ -n "$1" ]; then      
        while [ -n "$1" ]
        do
            case "$1" in 
            "-a"|"--admin-certificates") 
                cadmin=1
                shift 1
                ;;     
            "-ca"|"--root-ca-certificate") 
                ca=1
                shift 1
                ;;                           
            "-e"|"--elasticsearch-certificates") 
                celastic=1
                shift 1
                ;; 
            "-w"|"--wazuh-certificates") 
                cwazuh=1
                shift 1
                ;;   
            "-k"|"--kibana-certificates") 
                ckibana=1
                shift 1
                ;;                               
            "-d"|"--debug") 
                debugEnabled=1          
                shift 1
                ;;                                 
            "-h"|"--help")        
                getHelp
                ;;                                         
            *)
                getHelp
            esac
        done    

        if [ -n "${debugEnabled}" ]; then
            debug=""           
        fi

        if [[ -n "${cadmin}" ]]; then
            generateAdmincertificate
            logger "Admin certificates created."
        fi   

        if [[ -n "${ca}" ]]; then
            generateRootCAcertificate
            logger "Authority certificates created."
        fi                   

        if [[ -n "${celastic}" ]]; then
            generateElasticsearchcertificates
            logger "Elasticsearch certificates created."
        fi     

        if [[ -n "${cwazuh}" ]]; then
            generateFilebeatcertificates
            logger "Wazuh server certificates created."
        fi 

        if [[ -n "${ckibana}" ]]; then
            generateKibanacertificates
            logger "Kibana certificates created."
        fi                     
           
    else
        readInstances
        generateRootCAcertificate
        generateAdmincertificate
        generateElasticsearchcertificates
        generateFilebeatcertificates
        generateKibanacertificates
        cleanFiles
    fi

}
