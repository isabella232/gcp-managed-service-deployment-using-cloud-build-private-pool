terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.1"
    }

    random = {
      source = "hashicorp/random"
    }
  }

  required_version = ">= 1.0"
}

provider "google" {
}

provider "local" {
}

provider "random" {
}