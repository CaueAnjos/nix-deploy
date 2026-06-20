{runCommand}: drv:
# FIX: just dummy test
runCommand drv.pname {} ''
  mkdir -p "$out"
  echo "${drv.version}" > "$out/bundle.txt"
''
