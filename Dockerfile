FROM ubuntu:18.04 as build
ENV DEBIAN_FRONTEND="noninteractive" TZ="Asia/Dubai"
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
# Install Prereqs
RUN DEBIAN_FRONTEND=noninteractive \
    apt-get update -qq && \
    apt-get install -qq -y --no-install-recommends --no-install-suggests \
      apache2             \
      apache2-dev         \
      ca-certificates     \
      automake            \
      libcurl4-gnutls-dev \
      libpcre++-dev       \
      libtool             \
      libxml2-dev         \
      libyajl-dev         \
      lua5.2-dev          \
      pkgconf             \
      ssdeep              \
      git		  \
      php		  \
      wget            &&  \
    apt-get clean && rm -rf /var/lib/apt/lists/* 

# Download ModSecurity & compile ModSecurity
RUN mkdir -p /usr/share/ModSecurity && cd /usr/share/ModSecurity && \
    wget --quiet "https://github.com/SpiderLabs/ModSecurity/releases/download/v2.9.3/modsecurity-2.9.3.tar.gz" && \
    tar -xvzf modsecurity-2.9.3.tar.gz && cd /usr/share/ModSecurity/modsecurity-2.9.3/ && \
    ./autogen.sh && ./configure && \
    make && make install && make clean

FROM ubuntu:18.04

RUN DEBIAN_FRONTEND=noninteractive \
    apt-get update -qq && \
    apt-get install -qq -y --no-install-recommends --no-install-suggests \
      apache2             \
      libcurl3-gnutls     \
      libxml2             \
      libyajl2            \
      ssdeep           && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    mkdir -p /etc/modsecurity.d 

COPY --from=build /usr/lib/apache2/modules/mod_security2.so                              /usr/lib/apache2/modules/mod_security2.so
COPY ./modsecurity.conf  /etc/modsecurity.d/modsecurity.conf
COPY --from=build /usr/share/ModSecurity/modsecurity-2.9.3/unicode.mapping               /etc/modsecurity.d/unicode.mapping

RUN sed -i -e 's/ServerSignature On/ServerSignature Off/g' \
           -e 's/ServerTokens OS/ServerTokens Prod/g'  /etc/apache2/conf-enabled/security.conf && \
    echo "Include /etc/modsecurity.d/*.conf"                                          > /etc/apache2/mods-available/modsecurity.conf && \
    echo "LoadModule security2_module /usr/lib/apache2/modules/mod_security2.so" > /etc/apache2/mods-available/modsecurity.load && \
    echo 'ServerName localhost' >>  /etc/apache2/conf-enabled/security.conf && \
    echo "hello world" > /var/www/html/index.html && \
    a2enmod unique_id modsecurity
    
RUN mkdir /etc/apache2/coreruleset && cd /etc/apache2/coreruleset && \
    apt update && apt-get install -y git && git config --global http.sslVerify "false" && git clone https://github.com/coreruleset/coreruleset.git && \
    cd coreruleset && \
    mv crs-setup.conf.example crs-setup.conf && \
    mv rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf && \
    mv rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf.example rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf && \
    echo "<IfModule security2_module> \n \
                Include /etc/apache2/coreruleset/coreruleset/crs-setup.conf \n \
                Include /etc/apache2/coreruleset/coreruleset/rules/*.conf \n \
    </IfModule>" >> /etc/apache2/apache2.conf
    	
EXPOSE 80

CMD ["apachectl", "-D", "FOREGROUND"]
