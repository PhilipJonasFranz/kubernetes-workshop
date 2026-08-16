set -e

mkdir -p tmp

# Load environment variables for substitution.
set -a
source .env
set +a

# Build space-separated list of ${VAR} tokens exported by .env file
vars=$(grep -oE '^[[:space:]]*export[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' .env \
  | awk '{print "${"$2"}"}' | tr '\n' ' ')

# Collect directories whose names start with two digits
dirs=""
for d in [0-9][0-9]*/; do
  [ -d "$d" ] && dirs="$dirs ${d%/}"
done

# Substitute only the collected variables in-place across the matched directories
find $dirs -type f -exec sh -c '
  vars="$1"; shift
  for file do
    tmp=$(mktemp)
    envsubst "$vars" < "$file" > "$tmp" && mv "$tmp" "$file"
  done
' sh "$vars" {} +

rm -r tmp