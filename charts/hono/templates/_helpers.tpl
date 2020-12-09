#
# Copyright (c) 2019, 2020 Contributors to the Eclipse Foundation
#
# See the NOTICE file(s) distributed with this work for additional
# information regarding copyright ownership.
#
# This program and the accompanying materials are made available under the
# terms of the Eclipse Public License 2.0 which is available at
# http://www.eclipse.org/legal/epl-2.0
#
# SPDX-License-Identifier: EPL-2.0
#
{{/* vim: set filetype=mustache: */}}

{{/*
Expand the name of the chart.
*/}}
{{- define "hono.name" -}}
  {{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "hono.fullname" -}}
  {{- if .Values.fullnameOverride -}}
    {{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
  {{- else -}}
    {{- $name := default .Chart.Name .Values.nameOverride -}}
    {{- if contains $name .Release.Name -}}
      {{- .Release.Name | trunc 63 | trimSuffix "-" -}}
    {{- else -}}
      {{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "hono.chart" }}
  {{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create container image name.
The scope passed in is expected to be a dict with keys
- (mandatory) "dot": the root (".") scope
- (mandatory) "component": a dict with keys
  - (mandatory) "imageName"
  - (optional) "imageTag"
  - (optional) "containerRegistry"
  - (optional) "useImageType": should image type configuration be used
*/}}
{{- define "hono.image" }}
  {{- $tag := default .dot.Chart.AppVersion ( default .dot.Values.honoImagesTag .component.imageTag ) }}
  {{- $registry := default .dot.Values.honoContainerRegistry .component.containerRegistry }}

  {{- if and .useImageType ( contains "quarkus" .dot.Values.honoImagesType ) }}
  {{- printf "%s/%s-%s:%s" $registry .component.imageName .dot.Values.honoImagesType $tag -}}
  {{- else }}
  {{- printf "%s/%s:%s" $registry .component.imageName $tag -}}
  {{- end }}
{{- end }}

{{/*
Add standard labels for resources as recommended by Helm best practices.
*/}}
{{- define "hono.std.labels" -}}
app.kubernetes.io/name: {{ template "hono.name" . }}
helm.sh/chart: {{ template "hono.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
{{- end }}

{{/*
Add standard labels and name for resources as recommended by Helm best practices.
The scope passed in is expected to be a dict with keys
- "dot": the "." scope and
- "name": the value to use for the "name" metadata property
- "component": the value to use for the "app.kubernetes.io/component" label
*/}}
{{- define "hono.metadata" -}}
name: {{ .dot.Release.Name }}-{{ .name }}
namespace: {{ .dot.Release.Namespace }}
labels:
  app.kubernetes.io/name: {{ template "hono.name" .dot }}
  helm.sh/chart: {{ template "hono.chart" .dot }}
  app.kubernetes.io/managed-by: {{ .dot.Release.Service }}
  app.kubernetes.io/instance: {{ .dot.Release.Name }}
  app.kubernetes.io/version: {{ .dot.Chart.AppVersion }}
  {{- if .component }}
  app.kubernetes.io/component: {{ .component }}
  {{- end }}
{{- end }}

{{/*
Add standard match labels to be used in podTemplateSpecs and serviceMatchers.
The scope passed in is expected to be a dict with keys
- "dot": the "." scope and
- "component": the value of the "app.kubernetes.io/component" label to match
*/}}
{{- define "hono.matchLabels" -}}
app.kubernetes.io/name: {{ template "hono.name" .dot }}
app.kubernetes.io/instance: {{ .dot.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Add annotations for marking an object to be scraped by Prometheus.
*/}}
{{- define "hono.monitoringAnnotations" -}}
prometheus.io/scrape: "true"
prometheus.io/path: "/prometheus"
prometheus.io/port: {{ default .Values.healthCheckPort .Values.monitoring.prometheus.port | quote }}
{{- end }}


{{/*
Creates a headless Service for a Hono component.
The scope passed in is expected to be a dict with keys
- "dot": the "." scope and
- "name": the value to use for the "name" metadata property
- "component": the value of the "app.kubernetes.io/component" label to match
*/}}
{{- define "hono.headless.service" }}
{{- $args := dict "dot" .dot "component" .component "name" (printf "%s-headless" .name) }}
---
apiVersion: v1
kind: Service
metadata:
  {{- include "hono.metadata" $args | nindent 2 }}
spec:
  clusterIP: None
  selector:
    {{- include "hono.matchLabels" $args | nindent 4 }}
{{- end }}


{{/*
Configuration for the health check server of service components.
If the scope passed in is not 'nil', then its value is
used as the configuration for the health check server.
Otherwise, a secure health check server will be configured to bind to all
interfaces on the default port using the component's key and cert.
*/}}
{{- define "hono.healthServerConfig" -}}
healthCheck:
{{- if . }}
  {{- toYaml . | nindent 2 }}
{{- else }}
  port: 8088
  bindAddress: "0.0.0.0"
  keyPath: "/etc/hono/key.pem"
  certPath: "/etc/hono/cert.pem"
{{- end }}
{{- end }}


{{/*
Configuration for the service clients of protocol adapters.
The scope passed in is expected to be a dict with keys
- "dot": the root scope (".") and
- "component": the name of the adapter
*/}}
{{- define "hono.serviceClientConfig" -}}
{{- $adapter := default "adapter" .component -}}
messaging:
{{- if .dot.Values.amqpMessagingNetworkExample.enabled }}
  name: Hono {{ $adapter }}
  amqpHostname: hono-internal
  host: {{ .dot.Release.Name }}-dispatch-router
  port: 5673
  keyPath: /etc/hono/key.pem
  certPath: /etc/hono/cert.pem
  trustStorePath: /etc/hono/trusted-certs.pem
  hostnameVerificationRequired: false
{{- else }}
  {{- required ".Values.adapters.amqpMessagingNetworkSpec MUST be set if example AQMP Messaging Network is disabled" .dot.Values.adapters.amqpMessagingNetworkSpec | toYaml | nindent 2 }}
{{- end }}
command:
{{- if .dot.Values.amqpMessagingNetworkExample.enabled }}
  name: Hono {{ $adapter }}
  amqpHostname: hono-internal
  host: {{ .dot.Release.Name }}-dispatch-router
  port: 5673
  keyPath: /etc/hono/key.pem
  certPath: /etc/hono/cert.pem
  trustStorePath: /etc/hono/trusted-certs.pem
  hostnameVerificationRequired: false
{{- else }}
  {{- required ".Values.adapters.commandAndControlSpec MUST be set if example AQMP Messaging Network is disabled" .dot.Values.adapters.commandAndControlSpec | toYaml | nindent 2 }}
{{- end }}
tenant:
{{- if .dot.Values.deviceRegistryExample.enabled }}
  name: Hono {{ $adapter }}
  host: {{ .dot.Release.Name }}-service-device-registry
  port: 5671
  credentialsPath: /etc/hono/adapter.credentials
  trustStorePath: /etc/hono/trusted-certs.pem
  hostnameVerificationRequired: false
{{- else }}
  {{- required ".Values.adapters.tenantSpec MUST be set if example Device Registry is disabled" .dot.Values.adapters.tenantSpec | toYaml | nindent 2 }}
{{- end }}
registration:
{{- if .dot.Values.deviceRegistryExample.enabled }}
  name: Hono {{ $adapter }}
  host: {{ .dot.Release.Name }}-service-device-registry
  port: 5671
  credentialsPath: /etc/hono/adapter.credentials
  trustStorePath: /etc/hono/trusted-certs.pem
  hostnameVerificationRequired: false
{{- else }}
  {{- required ".Values.adapters.deviceRegistrationSpec MUST be set if example Device Registry is disabled" .dot.Values.adapters.deviceRegistrationSpec | toYaml | nindent 2 }}
{{- end }}
credentials:
{{- if .dot.Values.deviceRegistryExample.enabled }}
  name: Hono {{ $adapter }}
  host: {{ .dot.Release.Name }}-service-device-registry
  port: 5671
  credentialsPath: /etc/hono/adapter.credentials
  trustStorePath: /etc/hono/trusted-certs.pem
  hostnameVerificationRequired: false
{{- else }}
  {{- required ".Values.adapters.credentialsSpec MUST be set if example Device Registry is disabled" .dot.Values.adapters.credentialsSpec | toYaml | nindent 2 }}
{{- end }}
{{- if .dot.Values.prometheus.createInstance }}
resource-limits:
  prometheus-based:
    host: {{ template "hono.prometheus.server.fullname" .dot }}
{{- else if .dot.Values.prometheus.host }}
resource-limits:
  prometheus-based:
    host: {{ .dot.Values.prometheus.host }}
    port: {{ default "9090" .dot.Values.prometheus.port }}
{{- end }}
{{- end }}


{{/*
Add Quarkus related configuration properties to YAML file.
The scope passed in is expected to be a dict with keys
- "dot": the root scope (".") and
- "component": the name of the adapter
*/}}
{{- define "hono.quarkusConfig" -}}
{{- if ( contains "quarkus" .dot.Values.honoImagesType ) }}
quarkus:
  log:
    console:
      color: true
    level: INFO
    category:
      "org.eclipse.hono":
        level: INFO
      "org.eclipse.hono.adapter":
        level: INFO
      "org.eclipse.hono.service":
        level: INFO
  vertx:
    prefer-native-transport: true
{{- end }}
{{- end }}


{{/*
Create a fully qualified Prometheus server name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "hono.prometheus.server.fullname" -}}
{{- if .Values.prometheus.server.fullnameOverride -}}
{{- .Values.prometheus.server.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default "prometheus" .Values.prometheus.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- printf "%s-%s" .Release.Name .Values.prometheus.server.name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s-%s" .Release.Name $name .Values.prometheus.server.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}


{{/*
Adds a Jaeger Agent container to a template spec.
*/}}
{{- define "hono.jaeger.agent" }}
{{- $jaegerEnabled := or .Values.jaegerBackendExample.enabled .Values.jaegerAgentConf }}
{{- if $jaegerEnabled }}
- name: jaeger-agent-sidecar
  image: {{ .Values.jaegerAgentImage }}
  ports:
  - name: agent-compact
    containerPort: 6831
    protocol: UDP
  - name: agent-binary
    containerPort: 6832
    protocol: UDP
  - name: agent-configs
    containerPort: 5778
    protocol: TCP
  readinessProbe:
    httpGet:
      path: "/"
      port: 14271
    initialDelaySeconds: 5
  env:
  {{- if .Values.jaegerBackendExample.enabled }}
  - name: REPORTER_GRPC_HOST_PORT
    value: {{ printf "%s-jaeger-collector:14250" .Release.Name | quote }}
  - name: REPORTER_GRPC_DISCOVERY_MIN_PEERS
    value: "1"
  {{- else }}
  {{- range $key, $value := .Values.jaegerAgentConf }}
  - name: {{ $key }}
    value: {{ $value | quote }}
  {{- end }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Adds Jaeger client configuration to a container's "env" properties.
The scope passed in is expected to be a dict with keys
- "dot": the root scope (".") and
- "name": the value to use for the JAEGER_SERVICE_NAME (prefixed with the release name).
*/}}
{{- define "hono.jaeger.clientConf" }}
{{- $agentHost := printf "%s-jaeger-agent" .dot.Release.Name }}
- name: JAEGER_SERVICE_NAME
  value: {{ printf "%s-%s" .dot.Release.Name .name | quote }}
{{- if .dot.Values.jaegerBackendExample.enabled }}
- name: JAEGER_SAMPLER_TYPE
  value: "const"
- name: JAEGER_SAMPLER_PARAM
  value: "1"
{{- else if empty .dot.Values.jaegerAgentConf }}
- name: JAEGER_SAMPLER_TYPE
  value: "const"
- name: JAEGER_SAMPLER_PARAM
  value: "0"
{{- end }}
{{- end }}

{{/*
Adds volume mounts to a component's container.
The scope passed in is expected to be a dict with keys
- "conf": the component's configuration properties as defined in .Values
- "name": the name of the component.
Optionally, the scope my contain key
- "dot": the root scope (".") and
- "configMountPath": the mount path to use for the component's config secret
                     instead of the default "/etc/hono"
*/}}
{{- define "hono.container.secretVolumeMounts" }}
{{- $volumeName := printf "%s-conf" .name }}
- name: {{ $volumeName | quote }}
  {{- if .configMountPath }}
  mountPath: {{ .configMountPath | quote }}
  {{- else }}
  mountPath: "/etc/hono"
  {{- end }}
  readOnly: true
{{- with .conf.extraSecretMounts }}
{{- range $name,$spec := . }}
- name: {{ $name | quote }}
  mountPath: {{ $spec.mountPath | quote }}
  readOnly: true
{{- end }}
{{- end }}
{{-  with .dot }}
{{- if ( contains "quarkus" .Values.honoImagesType ) }}
- name: {{ $volumeName | quote }}
  mountPath: "/opt/hono/config"
  readOnly: true
{{- end }}
{{- end }}
{{- end }}

{{/*
Adds volume declarations to a component's pod spec.
The scope passed in is expected to be a dict with keys
- "conf": the component's configuration properties as defined in .Values
- "name": the name of the component
- "releaseName": the .Release.Name
Optionally, the scope my contain key
- "dot": the root scope (".")
*/}}
{{- define "hono.pod.secretVolumes" }}
{{- $volumeName := printf "%s-conf" .name }}
- name: {{ $volumeName | quote }}
  secret:
    secretName: {{ printf "%s-%s" .releaseName $volumeName | quote }}
{{- with .conf.extraSecretMounts }}
{{- range $name,$spec := . }}
- name: {{ $name | quote }}
  secret:
    secretName: {{ $spec.secretName | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Adds port type declarations to a component's service spec.
*/}}
{{- define "hono.serviceType" }}
{{- if eq .Values.platform "openshift" }}
  type: ClusterIP
{{- else if eq .Values.useLoadBalancer true }}
  type: LoadBalancer
{{- else }}
  type: NodePort
{{- end }}
{{- end }}

{{/*
Configures NodePort on component's service spec.
*/}}
{{- define "hono.nodePort" }}
{{- if ne .dot.Values.platform "openshift" }}
nodePort: {{ .port  }}
{{- end }}
{{- end }}




