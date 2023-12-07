#!/bin/sh

## params (.env)
# WORKDIR=
# GITHUB_TOKEN=
# AWS_ACCESS_KEY_ID=
# AWS_SECRET_ACCESS_KEY=
# AWS_REGION=
# AWS_DEFAULT_REGION=
# TF_CLI_ARGS_init=
# TF_MODULES_RESTORE_PATH=

setup() {
	local workdir=${1:-.}; shift
	local envfile=${1:-.env}; shift
	if [ ! -d "$workdir" ]; then
		echo "--> Work dir "$workdir" does not exist. Exiting..." >&2
		exit 0
	fi
	cd "$workdir"

	if [ -f "$envfile" ]; then
		local exportscript=$(mktemp)
		cat "$envfile" | grep -v "^\s*#.*" | sed 's:^:export :g' > "$exportscript"
		source "$exportscript"
		rm -f "$exportscript"
	fi

	create_gitconfig
	if [ -n "$TF_CLI_ARGS_init" ]; then
		restore_tf_modules \
			&& terraform init
	fi
}

teardown() {
	save_tf_modules \
		&& rm -f ~/.gitconfig
}

create_gitconfig() {
	[ -z "$GITHUB_TOKEN" ] && return 0
	cat >> ~/.gitconfig <<EOF
[url "https://oauth2:${GITHUB_TOKEN}@github.com"]
	insteadOf = https://github.com
EOF
}

restore_tf_modules() {
	local filename=.terraform.tar.gz
	local target="$TF_MODULES_RESTORE_PATH"/$filename
	if [ ! -d .terraform ] \
		&& [ -n "$TF_MODULES_RESTORE_PATH" ] \
		&& aws s3 ls "$target"; then
		echo '--> Restoring terraform modules...' >&2
		aws s3 cp "$target" ./"$filename" --quiet \
			&& tar -xzf "$filename" \
			&& rm -f "$filename"
	fi
}

save_tf_modules() {
	local filename=.terraform.tar.gz
	local target="$TF_MODULES_RESTORE_PATH"/$filename
	if [ -d .terraform ] && [ -n "$TF_MODULES_RESTORE_PATH" ]; then
		echo '--> Saving terraform modules...' >&2
		tar -czf "$filename" .terraform .terraform.lock.hcl \
			&& aws s3 cp "$filename" "$target" --quiet \
			&& rm -f "$filename"
	fi
}

parse_and_run_command() {
	echo "--> Executing '$COMMAND'..." >&2
	$COMMAND
}

main() {
	local workdir=$1; shift
	local envfile=$1; shift
	local command=$1; shift
	setup "$workdir" "$envfile"
	echo "--> Executing '$command'..." >&2
	$command
	ecode=$?
	teardown
	return $ecode
}

main "$@"

