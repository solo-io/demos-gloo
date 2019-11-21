# Gloo + Loop

Loop is a project we can use to implement record and replay of requests in a distributed system when things fail.

This is a prototype demo, giving the user a glimpse of its power.

## Install Gloo

This contains a custom build of Gloo with Envoy's tap filter extended to support the request recording we need:

```shell
kubectl apply -f gloo.yaml
```

You should be able to use a `glooctl` version < 1.0.0 to interact with this installation of Gloo

## Install Loop

```shell
kubectl apply -f loop.yaml
```

This will install the loop controller. To interact with it, you'll need the loop binary (see the  `bin` folder for your architecture -- rename the appropriate one to `loopctl` and put on the path). You'll need to expose the loop controller locally like this:

```shell
kubectl port-forward -n loop-system deployment/loop 5678
```

Now you should be able to use the loop binary of your architecture to list and replay  requests that are captured by the system (we've not set any up yet):

```shell
loopctl list
```

Replay:

```shell
loopctl replay --id 1
```

Note, you may have to set the destination explicitly:

```shell
loopctl replay --id 1 --destination gateway-proxy-v2.gloo-system
```

## Instructing Gloo to Capture certain requests

To prime the record/reply system, you'll want to give it instructions on what to capture. For example, to capture any unsuccessful requests, you'd write a Tap configuration like this:

```yaml
apiVersion: loop.solo.io/v1
kind: TapConfig
metadata:
  name: gloo
  namespace: loop-system
spec:
  match: responseHeaders[":status"] == prefix("2")
```

The example tap configuration (`tap.yaml`) will actually capture all successful requests just to show it works. Feel free to change it:

```shell
kubectl apply -f tap.yaml
```
