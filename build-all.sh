#!/bin/bash
set -e
set -o pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
REPO_URL="${REPO_URL:-rosskukulinski}"
JOBS=${JOBS:-2}

ERRORS="$(pwd)/errors"

build_and_push(){
	base=$1
	suite=$2
	build_dir=$3

	echo "Building ${REPO_URL}/${base}:${suite} for context ${build_dir}"
	docker build --rm --force-rm -t ${REPO_URL}/${base}:${suite} ${build_dir} || return 1

	# on successful build, push the image
	echo "                       ---                                   "
	echo "Successfully built ${base}:${suite} with context ${build_dir}"
	echo "                       ---                                   "


    docker push ${REPO_URL}/${base}:${suite}

	# also push the tag latest for "stable" tags
	if [[ "$suite" == "stable" ]]; then
		docker tag ${REPO_URL}/${base}:${suite} ${REPO_URL}/${base}:latest
		docker push ${REPO_URL}/${base}:latest
	fi
}

dofile() {
	f=$1
	image=${f%Dockerfile}
	base=${image%%\/*}
	build_dir=$(dirname $f)
	suite=${build_dir##*\/}
    echo "${image} ${base} ${build_dir} ${suite}"
	if [[ -z "$suite" ]] || [[ "$suite" == "$base" ]]; then
		suite=latest
	fi

	{
		$SCRIPT build_and_push "${base}" "${suite}" "${build_dir}"
	} || {
	# add to errors
	echo "${base}:${suite}" >> $ERRORS
}
echo
echo
}

main(){
	rm -Rf $ERRORS
	# get the dockerfiles
	IFS=$'\n'
	files=( $(find . -iname '*Dockerfile' | sed 's|./||' | sort) )
	unset IFS

	# build all dockerfiles
	echo "Running in parallel with ${JOBS} jobs."
	parallel --tag --verbose --ungroup -j"${JOBS}" $SCRIPT dofile "{1}" ::: "${files[@]}"

	if [[ ! -f $ERRORS ]]; then
		echo "No errors, hooray!"
	else
		echo "[ERROR] Some images did not build correctly, see below." >&2
		echo "These images failed: $(cat $ERRORS)" >&2
		exit 1
	fi
}

run(){
	args=$@
	f=$1

	if [[ "$f" == "" ]]; then
		main $args
	else
		$args
	fi
}

run $@