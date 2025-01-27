# Prometheus Operator Deployment Script for Contributors  

This script is a tool designed specifically for contributors to the Prometheus Operator codebase. It automates the process of packaging your customized version of the operator, setting up a Kubernetes cluster using `kind`, and deploying the operator for testing from the user's perspective.  

While the Prometheus Operator repository offers other ways to test the operator locally, this script is particularly useful when you need to test your changes in a real cluster environment. By streamlining the setup process, it saves you the time and effort of manually building and deploying your changes.  

---

## Key Features  

- **Cluster Management**: Automatically creates and manages `kind` clusters (including multi-node clusters).  
- **Image Building and Deployment**: Builds the Docker images for the operator and its components and deploys them into the cluster.  
- **Operator Deployment**: Deploys your version of the Prometheus Operator as a bundle, simulating real-world usage.  
- **Error Handling**: Includes clear and informative error messages to assist with troubleshooting.  
- **Customizability**: Supports options to configure the cluster, skip checks, and adjust logging levels.  

---

## Prerequisites  

Before using the script, ensure the following:  

1. **Installed Dependencies**:  
   - `kubectl`: Kubernetes command-line tool  
   - `docker`: Docker CLI  
   - `kind`: Kubernetes in Docker CLI  

   These tools must be installed and accessible in your system's `PATH`.  

2. **Prometheus Operator Repository**:  
   - Clone the Prometheus Operator repository from GitHub.  
   - The script requires the `--operator-dir` to point to the root directory of this repository.  

3. **Script Permissions**:  
   - After cloning, make the script executable:  
     ```bash
     chmod +x run-operator.sh
     ```  

---

## Usage  

```bash
./run-operator.sh [OPTIONS]
```  

### Options  

| Option                         | Short Flag  | Description                                                                                   |
|--------------------------------|-------------|-----------------------------------------------------------------------------------------------|
| `--operator-dir DIR`           | `-o DIR`    | Specify the operator's working directory (e.g., the Prometheus Operator repository root).     |
| `--debug-level LEVEL`          | `-d LEVEL`  | Set the debug level. Allowed values: `default` or `info`.                                     |
| `--kind-context CONTEXT`       | `-k CONTEXT`| Set the name of the `kind` cluster context. Default: `test`.                                  |
| `--kind-config FILE`           | `-K FILE`   | Specify a `kind` configuration file (e.g., for multi-node clusters).                          |
| `--skip-operator-check`        | `-s`        | Skip checking for existing Prometheus Operator instances in the cluster.                      |
| `--help`                       | `-h`        | Display the help message and exit.                                                            |
| `--cleanup`                    | `-c`        | Tear down and delete the `kind` cluster.                                                      |  

---

## Examples  

### 1. Deploy Your Operator into a Single-Node Cluster  

```bash
./run-operator.sh --operator-dir /path/to/operator
```  

This command builds and deploys your customized Prometheus Operator into a single-node `kind` cluster.  

---

### 2. Use the Default Multi-Node Configuration  

The repository includes a default `kind-multinode-config.yaml` file for creating multi-node clusters. Use it as follows:  

```bash
./run-operator.sh --kind-config /path/to/operator/kind-multinode-config.yaml --operator-dir /path/to/operator
```  

This will:  
- Create a multi-node cluster using the specified configuration.  
- Build and load the operator images.  
- Deploy the Prometheus Operator bundle to the cluster.  

---

### 3. Skip Existing Operator Check  

If you know it is safe to proceed without verifying for existing Prometheus Operator instances in the cluster, use the following:  

```bash
./run-operator.sh --skip-operator-check --operator-dir /path/to/operator
```  

---

### 4. Tear Down the Cluster  

To clean up the `kind` cluster after testing:  

```bash
./run-operator.sh --cleanup
```
### 5. Customizing Default Values
You can modify the default values in the script to suit your preferences and reduce the need to pass certain flags every time you run it. For example:  

1. **Set the `OPERATOR_DIR` Variable**:  
   By default, the `OPERATOR_DIR` variable is initialized to the `operator` directory in the current working directory:  

   ```bash
   OPERATOR_DIR=$(pwd)/operator
   ```  

   If you frequently use the same directory for the Prometheus Operator repository, you can set this variable to the desired directory directly in the script. For instance:  

   ```bash
   OPERATOR_DIR=/home/user/projects/prometheus-operator
   ```  

   This way, you won't need to specify the `--operator-dir` flag each time you run the script.  

2. **Modify Other Defaults**:  
   - **Cluster Context**: Update the `KIND_CONTEXT` variable to set a different default cluster context name.  
     ```bash
     KIND_CONTEXT=my-custom-cluster
     ```  
   - **Debug Level**: Change the `DEBUG_LEVEL` variable to `info` if you prefer detailed logs by default.  
     ```bash
     DEBUG_LEVEL=info
     ```  

3. **Save Changes**:  
   After editing the script, save your changes. These new defaults will be applied every time the script is run.  

By customizing these variables, you can streamline your workflow and avoid passing repetitive flags for commonly used settings.

---

## Workflow  

1. **Dependency Check**:  
   - Ensures `kubectl`, `docker`, and `kind` are installed.  

2. **Cluster Initialization**:  
   - Creates or reinitializes a `kind` cluster using the specified context and configuration.  

3. **Image Building**:  
   - Builds Docker images for the operator and its components:  
     - Prometheus Operator  
     - Prometheus Config Reloader  
     - Admission Webhook  
   - Tags the images using the current Git commit or defaults to `latest`.  

4. **Image Deployment**:  
   - Loads the built images into the `kind` cluster.  

5. **Operator Deployment**:  
   - Deploys the Prometheus Operator bundle to the cluster using `kubectl`.  

6. **Conflict Checks**:  
   - Ensures no other Prometheus Operator is running in the cluster unless explicitly skipped.  

---

## Notes  

- **Repository Root**: The `--operator-dir` flag must point to the root directory of the Prometheus Operator repository.  
- **Default Configuration**: Use the `kind-multinode-config.yaml` provided in the repository for multi-node clusters.  

---

## Default Multi-Node Configuration  

The repository provides a `kind-multinode-config.yaml` file to create multi-node clusters. Below is an example configuration:  

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
```  

Use this file with the `--kind-config` flag to create a multi-node cluster.  

---

## Troubleshooting  

1. **Missing Dependencies**:  
   - Ensure `kubectl`, `docker`, and `kind` are installed and accessible in your `PATH`.  

2. **Cluster Initialization Issues**:  
   - Verify the `kind` configuration file and ensure Docker is running.  

3. **Image Build Failures**:  
   - Check for issues in the `Dockerfile` paths or build arguments (`ARCH`, `GOARCH`, `GOOS`).  

4. **Deployment Errors**:  
   - Ensure the `bundle.yaml` file is up-to-date and matches the images being built.  
