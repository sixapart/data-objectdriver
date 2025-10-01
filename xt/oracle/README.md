# movabletype-oracle

## Setup

Build an oracle docker image beforehand. (oracle/database:19.3.0 for example)

In order to build one, `git clone` a repository.

```sh
git clone git@github.com:oracle/docker-images.git
cd docker-images/OracleDatabase/SingleInstance/dockerfiles/
```

Download zip file from [download page on oracle.com](https://www.oracle.com/database/technologies/oracle19c-linux-downloads.html#license-lightbox) and put it into `./19.3.0/` directory.

Build the image with following command.

```sh
./buildContainerImage.sh -v 19.3.0 -e
```

## Test

```sh
cd data-objectdriver
ORACLE_VERSION=19.3.0-ee docker compose -f ./xt/oracle/docker-compose.yml up
docker exec -it oracle-dod-1 prove -Ilib -It/lib t
```

## Inspect DB

```sh
docker exec -it oracle-dod-1 sh -c "NLS_LANG=JAPANESE_JAPAN.AL32UTF8 sqlplus system/test@oracle/global"
```

```sql
SET ECHO OFF
SET SERVEROUTPUT ON SIZE 1000000
SET PAGESIZE 999
SET LINESIZE 32000
select ...
```
