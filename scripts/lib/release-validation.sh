#!/usr/bin/env bash

validate_version() {
  [[ "$1" =~ ^[0-9]+[.][0-9]+[.][0-9]+([-.][0-9A-Za-z]+)*$ ]]
}

validate_build_version() {
  [[ "$1" =~ ^[0-9]+$ ]]
}
