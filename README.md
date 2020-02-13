# Deployment Tips

* When using JSON format, some terraform attributes need to be set to null, even when the docs shows as optional
  * Ref: https://github.com/terraform-providers/terraform-provider-aws/issues/8786#issuecomment-496935442
* Terranix strips out null attrs which causes a problem with some resources
* A quick workaround is to quote nulls and then strip them with sed prior to applying the config to terraform:

```
# terranix | sed 's/"null"/null/g' > deployment.tf.json; terraform apply
```
