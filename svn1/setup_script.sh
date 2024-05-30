#!/bin/bash

# 1. Base Installations
apt-get -y update && apt-get -y upgrade
apt-get install -y \
  git-core \
  git-svn \
  ruby \
  subversion \
  curl \
  python3-pip\
  xmlstarlet\
  gh # GitHub CLI
gem install svn2git
pip install pandas
pip install lxml
pip install openpyxl

## Exports
SVN_REPO_URL=https://eu-subversion.assembla.com/svn/anythingispossible^SVN.svn-demo/ # $1
SVN_REPO_NAME=anythingispossible^SVN.svn-demo # $2
JFROG_ARTIFACTORY=https://ayushsaini.jfrog.io
JFROG_ARTIFACTORY_REPO=demo-generic-local
GITHUB_REPO=svn-gh-test
GITHUB_HOST=https://www.github.com
GITHUB_ORG=NishkarshRaj

## Pre-Reqs
mkdir -p /csg/svn-git/
cd /csg/svn-git/
rm -rf users.txt binary_urls.txt
git config --global user.name "CSG_Bot"
git config --global user.email "bot@csg.com"
git config --global init.defaultBranch main

# 2. Create User Mapping
svn log ${SVN_REPO_URL} -q | awk -F '|' '/^r/ {gsub(/ /, "", $2); sub(" $", "", $2); print $2" = "$2" <"$2">"}' | sort -u > users.txt
## Format: <svn username> = fname lname <email>

## Git Ignores and remove binary from SVN source
## https://github.com/github/gitignore

# 3. Clone SVN repo & Initialize as Git Repository
git svn clone --authors-file=users.txt ${SVN_REPO_URL}
cd ${SVN_REPO_NAME}

# 4. Handling Binaries
find . -type f ! -path "*/.git/*" | while read -r file; do
    mime_type=$(file --mime-type -b "$file")
    case "$mime_type" in
        application/octet-stream|application/x-dosexec|application/x-dfont)
            binary_name=$(basename "$file")
            jfrog_url="${JFROG_ARTIFACTORY}/artifactory/${JFROG_ARTIFACTORY_REPO}/$binary_name"
            echo "$jfrog_url" > "${file}.url"
            git add "${file}.url"
            echo "$jfrog_url" >> binary_urls.txt
            ;;
    esac
done

git add binary_urls.txt

# 5. Read each JFrog URL from binary_urls.txt
while read -r jfrog_url; do
    # Extract the binary name from the JFrog URL
    binary_name=$(basename "$jfrog_url")

    # Find the path of the binary with the given name
    binary_path=$(find . -name "$binary_name")

    # Upload the binary file to JFrog using curl
    if ! curl -u "ayush.sai@statusneo.com:CSWC++@sa2023" --upload-file "$binary_path" "$jfrog_url"; then
        echo "Failed to upload $binary_path to JFrog"
        exit 1
    fi
done < binary_urls.txt


# 6. Making a list of all Mime Type files with original History.
svn ls --recursive ${SVN_REPO_URL} | while read -r file; do
    mime_type=$(svn propget svn:mime-type "${SVN_REPO_URL}/$file" 2>/dev/null)
    if [ -z "$mime_type" ]; then
        continue  # Skip files without the svn:mime-type property
    fi
    case "$mime_type" in
        application/octet-stream|application/x-dosexec|application/x-dfont)
            binary_name=$(basename "$file")
            # Check if the binary file is under version control
            if svn info "${SVN_REPO_URL}/$file" &>/dev/null; then
                svn log --xml "${SVN_REPO_URL}/$file" | \
                xmlstarlet sel -t -m "//logentry" -v "concat('$file,',author,'|',date,'|',msg)" -nl >> file_history.txt
            else
                echo "File '$file' is not under version control."
            fi
            ;;
    esac
done

# 6.5 [ Optional ] To remove bin files
git rm '*.bin'

# 7. Create Excel history & GitIgnore

svn log --xml ${SVN_REPO_URL} > svn_history.xml
echo -e 'import pandas as pd

# Load XML data into DataFrame
xml_data = pd.read_xml("svn_history.xml")

# Convert DataFrame to Excel
xml_data.to_excel("svn_history.xlsx", index=False)' > convert_to_excel.py
python3 convert_to_excel.py
echo -e '*.py
*.xml
!*.xlsx' > .gitignore


git commit -m "feat: migrate binaries to JFrog"
