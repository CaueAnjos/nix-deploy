{
  deployTools,
  join,
}: drv:
join {
  name = "${drv.pname or drv.name}-compact";
  paths = deployTools.mkReferences {
    inherit drv;
    mode = "runtime";
  };
}
