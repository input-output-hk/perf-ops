{ runCommand, extra-container }:

runCommand "jormungandr-containers" {
  extraContainer = "${extra-container}/bin/extra-container";
} ''
  mkdir -p $out
  cp -R ${./jormungandr}/* $out
  substituteAll ${./jormungandr}/create-extra-container.sh $out/create-extra-container.sh
''
