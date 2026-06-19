{
  writeShellApplication,
  referencesByPopularity,
  drv ? null,
  refs ? null,
}:
writeShellApplication {
  name = "copyclosure";
  runtimeEnv = {
    DRV = drv;
    REF =
      if refs == null
      then referencesByPopularity drv
      else refs;
  };
  text = builtins.readFile ../src/copyclosure/copyclosure.sh;
}
