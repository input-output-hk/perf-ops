{ runCommand, extra-container }:

runCommand "cardano-node-containers" {
  extraContainer = "${extra-container}/bin/extra-container";
} ''
  mkdir -p $out
  cp -R ${./cardano-node}/* $out
  substituteAll ${./cardano-node}/create-extra-container.sh $out/create-extra-container.sh
''
