NEXT_CONTENT_DIR_NAME='.NEXT'
NEXT_CONTENT_DIR="$PROJECT_BASE_DIR/$NEXT_CONTENT_DIR_NAME"
PREV_CONTENT_DIR_NAME='.PREV'
PREV_CONTENT_DIR="$PROJECT_BASE_DIR/$PREV_CONTENT_DIR_NAME"
DEST_DIR_NAME='dest'
SRC_DIR_NAME='src'

CONTENT_DIRS=$([ -z $UPDATES_SCRIPTS_ONLY ] && echo 'src template model' || echo 'model')
UPDATABLE_DIRS=$([ -z $UPDATES_SCRIPTS_ONLY ] && echo 'dest scripts doc .vscode' || echo 'scripts')
CONTENT_FILES=$([ -z $UPDATES_SCRIPTS_ONLY ] && echo '.editorconfig .gitattributes .gitignore README.md README_*.md model-schema-*.json' || echo '')

RECURSION_COUNT=1

main() {
  create_next_content_dir
  update_file_index
  while ! has_settled
  do
    (( $RECURSION_COUNT > $MAX_RECURSION )) && echo "Exceeded the maximum recursion depth: $MAX_RECURSION" && exit 1
    rm -rf $PREV_CONTENT_DIR
    cp -rf $NEXT_CONTENT_DIR $PREV_CONTENT_DIR
    generate
    RECURSION_COUNT=$(($RECURSION_COUNT + 1))
  done
  if [ -z $DRY_RUN ]
  then
    trap apply_next_content EXIT
  else
    git diff --no-index $NEXT_CONTENT_DIR $PROJECT_BASE_DIR
  fi
}

create_next_content_dir() {
  rm -rf $NEXT_CONTENT_DIR $PREV_CONTENT_DIR
  mkdir -p $NEXT_CONTENT_DIR
  (cd $PROJECT_BASE_DIR
    dirs=$(for each in $CONTENT_DIRS; do [ -d $each ] && echo $each || true; done)
    files=$(for each in $CONTENT_FILES; do [ -f $each ] && echo $each || true; done)
    [ -z "$dirs" ] || cp -rf $dirs $NEXT_CONTENT_DIR
    [ -z "$files" ] || cp -f $files $NEXT_CONTENT_DIR
  )

  local src_dir="$NEXT_CONTENT_DIR/$SRC_DIR_NAME"
  local dest_dir="$NEXT_CONTENT_DIR/$DEST_DIR_NAME"

  rm -rf $dest_dir
  if [ -d $src_dir ]
  then
    cp -rf $src_dir $dest_dir
  else
    mkdir -p $dest_dir
  fi
}

normalize_path() {
  local path=$1
  if [[ $path == ./* ]]
  then
    echo "${PROJECT_BASE_DIR}/$path"
  elif [[ $path == /* ]]
  then
    echo $path
  else
    echo "$NEXT_CONTENT_DIR/$path"
  fi
}

update_file_index() {
  local index_dir="$NEXT_CONTENT_DIR/model/project"
  mkdir -p $index_dir
  cat <<EOF > "$index_dir/sources.yaml"
project:
  sources:$(file_list | sort -d)
EOF
}

file_list() {
  (cd "$PROJECT_BASE_DIR"
    local separator="\n  - "
    local dirs=
    [ -d ./model ] && dirs="$dirs ./model"
    [ -d ./template ] && dirs="$dirs ./template"
    [ -d ./src ] && dirs="$dirs ./src"
    find $dirs -type f | while read -r file
    do
      printf "$separator\"${file:2}\""
    done
    printf "\n"
  )
}

generate() {
  {{#if project.module_repositories.local ~}}
  LOCAL_MODULE_REPOSITORY=${LOCAL_MODULE_REPOSITORY:-"$PROJECT_BASE_DIR/{{project.module_repositories.local}}"}
  {{/if}}
  local generator_script="$PROJECT_BASE_DIR/scripts/laplacian-generate.sh"
  local schema_file_path="$(normalize_path 'model-schema-full.json')"
  local schema_option=
  if [ -f $schema_file_path ]
  then
    schema_option="--model-schema $(normalize_path 'model-schema-full.json')"
  fi
  $generator_script ${VERBOSE:+'-v'} \
    {{#each project.all_plugins as |plugin| ~}}
    --plugin '{{plugin.artifact_id}}' \
    {{/each}}
    {{#each project.all_templates as |template| ~}}
    --template '{{template.artifact_id}}' \
    {{/each}}
    {{#each project.all_models as |model| ~}}
    --model '{{model.artifact_id}}' \
    {{/each}}
    {{#if entities}}
    $schema_option \
    {{/if}}
    --model-files $(normalize_path 'model/') \
    {{#each project.model_files as |files| ~}}
    --model-files $(normalize_path '{{files}}') \
    {{/each}}
    --template-files $(normalize_path 'template/') \
    {{#each project.template_files as |files| ~}}
    --template-files $(normalize_path '{{files}}') \
    {{/each}}
    --target-dir "$NEXT_CONTENT_DIR_NAME" \
    --local-repo "$LOCAL_MODULE_REPOSITORY"
}

has_settled() {
  [ $RECURSION_COUNT == 1 ] && return 1
  [ -d $NEXT_CONTENT_DIR ] || return 1
  [ -d $PREV_CONTENT_DIR ] || return 1
  diff -r $NEXT_CONTENT_DIR $PREV_CONTENT_DIR > /dev/null
}

apply_next_content() {
  (cd $PROJECT_BASE_DIR
    dirs=$(for each in $UPDATABLE_DIRS; do [ -d $each ] && echo $each || true; done)
    files=$(for each in $CONTENT_FILES; do [ -f $each ] && echo $each || true; done)
    [ -z "$dirs" ] || rm -rf $dirs
    [ -z "$files" ] || rm -f $files
  )

  (cd $NEXT_CONTENT_DIR
    dirs=$(for each in $UPDATABLE_DIRS; do [ -d $each ] && echo $each || true; done)
    files=$(for each in $CONTENT_FILES; do [ -f $each ] && echo $each || true; done)
    [ -z "$dirs" ] || cp -rf $dirs $PROJECT_BASE_DIR
    [ -z "$files" ] || cp -f $files $PROJECT_BASE_DIR
  )

  rm -rf $NEXT_CONTENT_DIR $PREV_CONTENT_DIR
}
