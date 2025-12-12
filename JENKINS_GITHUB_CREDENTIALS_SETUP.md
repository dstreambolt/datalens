# Jenkins GitHub SSH Credentials Setup Guide

## Issue
```
ERROR: Error cloning remote repo 'origin'
hudson.plugins.git.GitException: Command "git fetch --tags --force --progress -- https://github.com/dstreambolt/dstream_cloud.git +refs/heads/*:refs/remotes/origin/*" returned status code 128:
stderr: remote: Invalid username or token.
Password authentication is not supported for Git operations.
fatal: Authentication failed for 'https://github.com/dstreambolt/dstream_cloud.git/'
```

**Root Cause**: Jenkins was trying to use HTTPS without credentials to clone a private GitHub repository.

**Solution**: Use SSH authentication with GitHub deploy keys or SSH credentials.

---

## Fix Applied to Jenkinsfile ✅

### Changes Made

1. **Changed Git URL**:
   - Before: `https://github.com/dstreambolt/dstream_cloud.git`
   - After: `git@github.com:dstreambolt/dstream_cloud.git` ✅

2. **Added Credentials Parameter**:
   ```groovy
   string(
       name: 'GIT_CREDENTIALS_ID',
       defaultValue: 'jenkins-github-ssh',
       description: 'Jenkins credentials ID for GitHub SSH access'
   )
   ```

3. **Updated Checkout Stage**:
   ```groovy
   checkout([
       $class: 'GitSCM',
       branches: [[name: "*/${params.GIT_BRANCH}"]],
       userRemoteConfigs: [[
           url: env.REPO_URL,
           credentialsId: params.GIT_CREDENTIALS_ID  // ← Added
       ]]
   ])
   ```

---

## Setup Instructions

### Option 1: Add SSH Credentials to Jenkins (Recommended)

#### Step 1: Generate SSH Key (if not exists)

On Jenkins server:
```bash
# SSH to Jenkins server
ssh ubuntu@13.232.132.240

# Generate SSH key
ssh-keygen -t ed25519 -C "jenkins@dstreambolt.com" -f ~/.ssh/jenkins_github_key

# Display public key
cat ~/.ssh/jenkins_github_key.pub
```

Copy the public key output.

---

#### Step 2: Add SSH Key to GitHub

1. Go to GitHub repository: https://github.com/dstreambolt/dstream_cloud

2. Navigate to: **Settings** → **Deploy keys** → **Add deploy key**

3. Fill in:
   - **Title**: `Jenkins DStreamBolt`
   - **Key**: Paste the public key from Step 1
   - **Allow write access**: ✅ (if Jenkins needs to push)

4. Click **Add key**

---

#### Step 3: Add Private Key to Jenkins

1. Open Jenkins: http://13.232.132.240:8081/

2. Navigate to: **Manage Jenkins** → **Credentials** → **System** → **Global credentials**

3. Click **Add Credentials**

4. Fill in:
   - **Kind**: SSH Username with private key
   - **ID**: `jenkins-github-ssh`
   - **Description**: `GitHub SSH for DStreamBolt`
   - **Username**: `git`
   - **Private Key**: Select "Enter directly"
     - Click **Add**
     - Paste the private key from `~/.ssh/jenkins_github_key`
   - **Passphrase**: (leave empty if no passphrase)

5. Click **OK**

---

#### Step 4: Test SSH Connection

On Jenkins server:
```bash
# Test GitHub SSH connection
ssh -T git@github.com

# Expected output:
# Hi dstreambolt/dstream_cloud! You've successfully authenticated, but GitHub does not provide shell access.
```

---

#### Step 5: Run Jenkins Job

1. Go to Jenkins job: **DStreamBolt-Deploy-Ingestion**

2. Click **Build with Parameters**

3. Parameters should show:
   - `GIT_CREDENTIALS_ID`: `jenkins-github-ssh` (default)

4. Click **Build**

Expected output:
```
📥 Checking out code from repository...
Repository: git@github.com:dstreambolt/dstream_cloud.git
Branch: main
Credentials: jenkins-github-ssh
✅ Checked out commit: abc1234
```

---

### Option 2: Use Existing SSH Key

If Jenkins server already has SSH access to GitHub:

#### Step 1: Locate Existing SSH Key

```bash
# On Jenkins server
ls -la ~/.ssh/
# Look for: id_rsa, id_ed25519, or jenkins_github_key
```

#### Step 2: Verify GitHub Access

```bash
ssh -T git@github.com
```

If this works, proceed to Step 3.

#### Step 3: Add to Jenkins Credentials

Follow "Step 3: Add Private Key to Jenkins" from Option 1 above.

---

### Option 3: Use GitHub Personal Access Token (Alternative)

If SSH is not an option, use Personal Access Token:

#### Step 1: Create GitHub PAT

1. Go to: https://github.com/settings/tokens
2. Click **Generate new token (classic)**
3. Settings:
   - **Note**: `Jenkins DStreamBolt`
   - **Expiration**: 90 days (or custom)
   - **Scopes**: ✅ `repo` (full control)
4. Click **Generate token**
5. **Copy the token immediately** (won't be shown again!)

#### Step 2: Add to Jenkins

1. Jenkins → **Manage Jenkins** → **Credentials** → **Global** → **Add Credentials**
2. Fill in:
   - **Kind**: Username with password
   - **ID**: `jenkins-github-https`
   - **Username**: `your-github-username`
   - **Password**: Paste the PAT token
3. Click **OK**

#### Step 3: Update Jenkinsfile

Change in jenkins job parameters:
```groovy
GIT_CREDENTIALS_ID: jenkins-github-https
```

And update REPO_URL to HTTPS:
```groovy
environment {
    REPO_URL = 'https://github.com/dstreambolt/dstream_cloud.git'
}
```

---

## Troubleshooting

### Error: "Host key verification failed"

**Fix**: Add GitHub to known_hosts:
```bash
# On Jenkins server
ssh-keyscan github.com >> ~/.ssh/known_hosts
```

### Error: "Permission denied (publickey)"

**Causes**:
1. SSH key not added to GitHub
2. Wrong key used
3. Key has passphrase but not provided

**Debug**:
```bash
# Test with verbose output
ssh -vT git@github.com

# Check which key is being used
ssh-add -l
```

**Fix**:
- Ensure public key is added to GitHub deploy keys
- Verify private key is added to Jenkins credentials
- If key has passphrase, provide it in Jenkins credentials

### Error: "Credentials not found: jenkins-github-ssh"

**Cause**: Credential ID doesn't exist in Jenkins

**Fix**:
1. Check credentials list: Jenkins → Manage Jenkins → Credentials
2. Verify ID matches: `jenkins-github-ssh`
3. If missing, add it (see Step 3 above)

### Error: "Could not read from remote repository"

**Causes**:
1. Deploy key doesn't have read access
2. Repository is private and key not authorized
3. SSH key format incorrect

**Fix**:
1. Verify deploy key is added to GitHub repository
2. Test SSH connection: `ssh -T git@github.com`
3. Regenerate SSH key if needed

---

## Verification

### 1. Test Jenkins Credentials

In Jenkins Pipeline Syntax:
1. Go to job → **Pipeline Syntax** → **Snippet Generator**
2. Sample Step: `git: Git`
3. Repository URL: `git@github.com:dstreambolt/dstream_cloud.git`
4. Credentials: Select `jenkins-github-ssh`
5. Click **Generate Pipeline Script**
6. Copy and test in Pipeline console

### 2. Test Full Deployment

Run the Jenkins job with parameters:
```
TARGET_IPS: 13.201.43.125
GIT_BRANCH: main
GIT_CREDENTIALS_ID: jenkins-github-ssh
```

Expected output:
```
[Pipeline] stage
[Pipeline] { (Checkout Code)
[Pipeline] echo
📥 Checking out code from repository...
[Pipeline] echo
Repository: git@github.com:dstreambolt/dstream_cloud.git
[Pipeline] echo
Branch: main
[Pipeline] echo
Credentials: jenkins-github-ssh
[Pipeline] checkout
Cloning the remote Git repository
Cloning repository git@github.com:dstreambolt/dstream_cloud.git
 > git init /var/lib/jenkins/workspace/DStreamBolt-Deploy-Ingestion
 > git fetch --tags --force --progress -- git@github.com:dstreambolt/dstream_cloud.git +refs/heads/*:refs/remotes/origin/*
 > git config remote.origin.url git@github.com:dstreambolt/dstream_cloud.git
Checking out Revision abc1234
[Pipeline] script
[Pipeline] {
[Pipeline] sh
[Pipeline] echo
✅ Checked out commit: abc1234
```

---

## Security Best Practices

1. **Use Deploy Keys** (read-only access recommended)
   - One key per repository
   - Limited scope
   - Easy to revoke

2. **Rotate Keys Regularly**
   - Update every 90 days
   - Use key expiration if supported

3. **Monitor Access**
   - Check GitHub audit log
   - Review deploy key usage

4. **Use SSH over HTTPS**
   - More secure
   - Better for automation
   - No token expiration issues

---

## Quick Reference

### Jenkins Credentials ID
```
jenkins-github-ssh
```

### Git Repository URL (SSH)
```
git@github.com:dstreambolt/dstream_cloud.git
```

### Test SSH Connection
```bash
ssh -T git@github.com
```

### Jenkins Credentials Location
```
Jenkins → Manage Jenkins → Credentials → System → Global credentials
```

### GitHub Deploy Keys Location
```
GitHub → Repository → Settings → Deploy keys
```

---

## Summary

✅ **Problem**: Jenkins couldn't clone GitHub repository (HTTPS auth failed)  
✅ **Solution**: Changed to SSH authentication  
✅ **Changes**: Updated Jenkinsfile to use SSH and credentials  
✅ **Setup Required**: Add SSH key to Jenkins and GitHub  
✅ **Status**: Ready to use after credentials setup  

---

**Next Steps**:
1. ⏳ Add SSH credentials to Jenkins (choose Option 1 or 2 above)
2. ⏳ Test GitHub connection: `ssh -T git@github.com`
3. ⏳ Run Jenkins job with `GIT_CREDENTIALS_ID=jenkins-github-ssh`
4. ✅ Verify successful checkout

**Created**: December 12, 2025  
**Status**: Awaiting credentials setup

