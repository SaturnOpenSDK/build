#!/bin/sh

# Usage:

# ./setup.sh [--force | --no-force]
#            [--clone | --download]
#            [--https | --ssh]
#            [--help | -h]

# --force | --no-force

#     If --force is specified, attempt to remove the existing repository
#     before cloning or downloading. If the removal fails, the old version
#     will be used, but a warning printed.  Default --no-force.

# --clone | --download

#     If --clone is specified, attempt to clone the repository, otherwise if
#     --download is specified, attempt to download a tarball file of the
#     repository.  Default --download.

# --https | --ssh

#     If --clone is specified, the --https and --ssh flags are used to
#     select which transport git should use. Default --https.
#
#

# --help | -h

#     Print out a brief help about this script and return with an error code.

# Note that earlier versions allowed specification of a location where the
# tools were to be downloaded. However recent versions do not download the SDK
# directory, so the script will only work if downloading is done in a fixed
# location relative to the pre-existing SDK directory (which contains this
# script).

# The script returns 1 on failure and 0 on success. Failure to delete a
# pre-existing version when specifying --force is not considered a failure.


################################################################################
#                                                                              #
#			                         Shell functions                                 #
#                                                                              #
################################################################################


# Function to print an error to stdout
# @param[in] $1 message
echo_error () {
  echo "ERROR: $1"
}

# Function to print an error to stdout
# @param[in] $1 message
echo_warning () {
  echo "WARNING: $1"
}

# Function to record error to log
# @param[in] $1 message
log_error () {
  echo_error "$1" | tee -a ${log}
}

# Function to record warning to log
# @param[in] $1 message
log_warning () {
  echo_warning "$1" | tee -a ${log}
}

# Function to download a file

# @param[in] $1 url
# @param[in] $2 output file
# @param[in] $3 options (optional)

# @return the result of the underlying call or 1 if no utility is found
download ()
{
  url=$1
  outfile=$2
  options=$3

  wget --version >> /dev/null 2>&1
  if [ $? -eq 0 ]
  then
    case ${options} in
      silent)
        wget --quiet --continue --output-document="${outfile}" ${url}
      ;;
      *)
        wget --quiet --show-progress --progress=bar:force:noscroll --continue --output-document="${outfile}" ${url}
      ;;
    esac
  else
    curl --version >> /dev/null 2>&1
    if [ $? -eq 0 ]
    then
      case ${options} in
        silent)
          curl -C - --silent --url "${url}" --output "${outfile}"
        ;;
        *)
          curl -C - --progress-bar --url "${url}" --output "${outfile}"
        ;;
      esac
    else
      log_error "no download utility found"
      return 1
    fi
  fi
  return $?
}


# Function to extract an archive

# @param[in] $1 filename
# @param[in] $2 destination (optional)

# @return 0 on success, 1 on failure.
unpack ()
{
  filename=$1
  destination=$2
  if ! eval "tar xf ${filename}" >> ${log} 2>&1
  then
    log_error "Unable to unpack ${filename}"
    return 1
  fi

  if [ "x$destination" != "x" ]
  then
    if ! mv `echo ${filename} | sed -e "s/\(.*\).tar.[a-z]\{2,3\}/\1/"` ${destination} >> ${log} 2>&1
    then
      log_error "Unable to move unpacked dir to ${destination}"
      return 1
    fi
  fi
}



# Function to clone a git repository, checking out the relevant branch.

# The cloned repository will name its remote "KallistiOS".

# @param[in] $1  The tool to clone
# @param[in] $2  The full repository URL
# @param[in] $3  The branch to checkout

# @return 0 on success, 1 on failure. Note that failure to remove components
#         when --force is in action is not considered a failure.
clone_tool()
{
  tool=$1
  repo_url=$2
  branch=$3

  # If old source exists, delete
  if [ "${force}" = "true" ]
  then
    if ! rm -rf ${tool} >> ${log} 2>&1
    then
      log_warning "Unable to delete old ${tool}"
    fi
  fi

  # Clone git repository if it does not already exist
  if [ -e ${tool} ]
  then
    echo "${tool} already cloned."
  else
    echo "Cloning ${tool}..."
    if ! git clone -q -o KallistiOS -b ${branch} ${repo_url} ${tool} >> ${log} 2>&1
    then
      log_error "Unable to clone ${tool}"
      return 1
    fi
  fi
}

# Function to either download a tool or clone a git repository from GitHub,
# checking out the relevant branch.

# @param[in] $1 The GitHub repo (within KallistiOS) to clone/download.
# @param[in] $2 The branch to checkout/download.
# @param[in] $3 Github organization.

# @return  The result of the underlying call to clone or download a tool.
github_tool ()
{
  repo=$1
  branch=$2
  organization=$3

  if [ "${clone}" = "true" ]
  then
    # If old source exists, delete
    if [ "${force}" = "true" ]
    then
      if ! rm -rf ${repo} >> ${log} 2>&1
      then
        log_warning "Unable to delete old ${tool}"
      fi
    fi

    # Clone git repository if it does not already exist
    if [ -e ${repo} ]
    then
      echo "${repo} already cloned."
    else
      echo "Cloning ${repo}..."
      if ! git clone -q -b ${branch} ${git_transport_prefix}/${organization}/${repo}.git >> ${log} 2>&1
      then
        log_error "Unable to clone ${tool}"
        return 1
      fi
    fi

#    clone_tool "${git_transport_prefix}/${organization}/${repo}" "${branch}"
  else
  # If --force is in action and old source exists, attempt delete
    if [ "${repo}" = "true" ]
    then
      if ! rm -rf ${repo} >> ${log} 2>&1
      then
        log_warning "Unable to delete old ${repo}"
      fi
    fi

    if [ -e "${repo}" ]
    then
      echo "${repo} already downloaded."
    else
      echo "Downloading repository: \"${repo}\" - branch: \"${branch}\""
      download "${git_transport_prefix}/${organization}/${repo}/archive/${branch}.tar.gz" "${repo}-${branch}.tar.gz"
      echo "Unpacking ${repo}..."
      unpack "${repo}-${branch}.tar.gz" "${repo}"
    fi
  fi
}

# Function to download a toolchain component

# @param[in] $1 Component name
# @param[in] $2 version
# @param[in] $3 gnu mirror URL (optional)

# @return 0 on success, anything else indicates failure
gnu_download_tool ()
{
  tool=$1
  version=$2
  target=${tool}-${version}
  urlbase=$3

  if [ "${urlbase}" = "" ]
  then
    urlbase=${gnu_url}
  fi

  filename=""
  sha512sum=""

# If --force is in action and old source exists, attempt delete
  if [ "${force}" = "true" ]
  then
    if ! rm -rf ${target} >> ${log} 2>&1
    then
      log_warning "Unable to delete old ${target}"
    fi
  fi

# Download and unpack source if it does not already exist
  if [ -e "${target}" ]
  then
    echo "${tool} already downloaded."
  else
    echo "Locating ${target}..."
# check the locations it /might/ be
    for directory in \
        "${urlbase}/${tool}" \
        "${urlbase}/${tool}/releases" \
        "${urlbase}/${tool}/releases/${target}" \
        "${urlbase}/${tool}/${version}" \
        "${urlbase}/${tool}/snapshots" \
        "${urlbase}/${tool}/snapshots/${target}" \
        "error"
    do
      if [ ${directory} = "error" ]
      then
        log_error "Unable to locate ${target} on server"
        return 1
      fi
      rm checksums.txt >> /dev/null 2>&1
      touch checksums.txt >> /dev/null 2>&1
      if download "${directory}/sha512.sum" "checksums.txt" "silent"
      then
        output=`grep "${target}.tar" checksums.txt`
        if [ "${output}" != "" ]
        then
          break
        fi
      fi
    done

    for line in `grep "${target}.tar" checksums.txt | sed -e "s/\([0-9a-f]\{128\}\)  .*.tar.\([a-z]\{2,3\}\)/\1:\2/"`
    do
      this_sha512sum=`echo ${line} | cut -d ':' -f 1`

      case `echo ${line} | cut -d ':' -f 2` in
        gz)
          if [ "${filename}" = "" ]
          then
            sha512sum=${this_sha512sum}
            filename=${target}.tar.gz
          fi
        ;;
        bz2)
          sha512sum=${this_sha512sum}
          filename=${target}.tar.bz2
        ;;
        xz)
          sha512sum=${this_sha512sum}
          filename=${target}.tar.xz
          break
        ;;
        *)
          log_error "parsing checksums.txt for ${target} from ${directory}"
          return 1
        ;;
      esac
    done

    echo "Downloading ${target}..."
    if ! download "${directory}/${filename}" "${filename}"
    then
      log_error "Unable to download ${tool}"
      return 1
    fi

    if [ "${validate}" = "true" ]
    then
      echo "Validating ${target}..."
      checksum=`sha512sum ${filename} | cut -d ' ' -f 1`

      if [ "${checksum}" != "${sha512sum}" ]
      then
        print_error "checksum failure: expected ${sha512sum} but got ${checksum}"
        log_error "download for ${target} does not match checksum in checksums.txt"
        return 1
      else
        echo "Download validated."
      fi
    fi

    rm checksums.txt >> /dev/null 2>&1

    echo "Unpacking ${target}..."
    if ! unpack "${filename}"
    then
      log_error "Unable to unpack ${tool}"
      return 1
    fi
  fi
}


# Function that loops over all component versions and downloads them

# @return 0 on success, anything else indicates failure
download_components()
{
  OLD_IFS=${IFS}
  IFS="
" # We only want the newline character

  res="ok"
  for line in `cat ${basedir}/components.conf | grep -v '^#' | grep -v '^$'`
  do
    class=`echo ${line} | cut -d ':' -f 1`
    case ${class} in
      toolchain)
        name=`      echo ${line} | cut -d ':' -f 2`
        version=`   echo ${line} | cut -d ':' -f 3`
        forced_url=`echo ${line} | cut -d ':' -f 4`

        if ! gnu_download_tool "${name}" "${version}" "${forced_url}"
        then
          res="fail"
          break
        fi
      ;;

      dreamcast)
        repo=`  echo ${line} | cut -d ':' -f 2`
        branch=`echo ${line} | cut -d ':' -f 3`
        organization=`  echo ${line} | cut -d ':' -f 4`
        if [ "${branch}" = "" ]
        then
          branch="master"
        fi
        if [ "${organization}" = "" ]
        then
          organization="KallistiOS"
        fi

        if ! github_tool "${repo}" "${branch}" "${organization}"
        then
          res="fail"
          break
        fi
      ;;

      lib)
        name=`echo ${line} | cut -d ':' -f 2`
        url=` echo ${line} | cut -d ':' -f 3`

        if ! lib_tool "${name}" "${url}"
        then
          res="fail"
          break
        fi
      ;;

      *)
        echo Ignoring ${class} ${tool}
      ;;
    esac
  done


  # Restore IFS before returning
  IFS=${OLD_IFS}
  [ "${res}" = "ok" ]
}


# Function to check for relative directory and makes it absolute

# @param[in] $1  The directory to make absolute if necessary.
absolutedir()
{
  case ${1} in
    /*)
	    echo "${1}"
    ;;

    *)
	    echo "${PWD}/${1}"
    ;;
  esac
}


################################################################################
#                                                                              #
#                              Parse arguments                                 #
#                                                                              #
################################################################################

# Defaults

force="false"
clone="false"
git_transport_prefix="https://github.com"
gnu_url="ftp://gcc.gnu.org/pub"

basedir=`dirname $0`
basedir=`absolutedir "${basedir}"`
builddir="${basedir}/builds"
originaldir=`pwd`

installdir="/usr"

until
  opt=$1
  case ${opt} in

    --force)
      force="true"
    ;;

    --no-force)
      force="false"
    ;;

    --clone)
      clone="true"
    ;;

    --download)
      clone="false"
    ;;

    --ssh)
      git_transport_prefix="git@github.com:"
    ;;

    --https)
      git_transport_prefix="https://github.com"
    ;;

    ?*)
      echo "Usage: ./setup.sh [--force | --no-force]"
      echo "                  [--clone | --download]"
      echo "                  [--https | --ssh]"
      echo "                  [--help | -h]"
      exit 1
    ;;

    *)
    ;;
  esac
  [ "x${opt}" = "x" ]
do
  shift
done


################################################################################
#                                                                              #
#                              Initialize setup                                #
#                                                                              #
################################################################################

# Determine the number of processes to use for building
makejobs=`nproc --all`
if [ $? -ne 0 ]
then
  makejobs=`sysctl hw.ncpu | awk '{print $2}'`
  if [ $? -ne 0 ]
  then
    makejobs="1"
  fi
fi

# Create and then move to builddir location

if [ ! -e "${builddir}" ]
then
  if ! mkdir "${builddir}"
  then
    print_error "Unable to create directory for downloads/clones"
    exit 1
  fi
fi

if ! cd "${builddir}"
then
  print_error "Unable to change to directory for downloads/clones"
  exit 1
fi

# Set up a log file
log="${builddir}/build-$(date +%F-%H%M).log"
rm -f "${log}"

echo "Logging to ${log}"

################################################################################
#                                                                              #
#                            Download everything                               #
#                                                                              #
################################################################################

# Download all components defined in 'components.conf'
if ! download_components
then
  cd "${originaldir}"
  log_error "Failed to download some components"
  exit 1
fi

if [ "${res}" = "ok" ]
then
  echo "Downloads complete"
else
  echo "Downloads incomplete - see log for failures"
fi


################################################################################
#                                                                              #
#                              Build everything                                #
#                                                                              #
################################################################################

for dir in `ls -1 -d -b ${builddir}/*/`
do
  echo dir: ${dir}

#make -j${makejobs} -C ${dir} DESTDIR="${installdir}" >> ${log} 2>&1
#make -C ${dir} install DESTDIR="${installdir}" >> ${log} 2>&1

done

cd "${originaldir}"