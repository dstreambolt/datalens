# Jenkins GitHub Setup Complete! 🎉

## ✅ What Was Done

1. ✅ SSH key generated for Jenkins user on DevOps node
2. ✅ GitHub added to Jenkins known_hosts
3. ✅ Private key saved locally for reference
4. ✅ Jenkins service verified as running

## 🔑 SSH Public Key Generated

The following SSH public key was generated and needs to be added to GitHub:

```
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCxUxibyRmlPDzuySJoql7MLEB/1H+9x+ymFzp/qAzXpqahlld6FNwtEwB7hgfbZo+1BNGQaxq89Ldl0FOeXec734uJFXjQrXCtxaG3pBO4uqThk6L3Ickt25qLqEBAfMCyX0k6hRpy2ZNzrxD8NrpUMPUyTOxmSKhNFDdksfwUyhp4Lax91TF86nYuCVyMSICHG/OqQCEfIOUiLcyDIGT1NPeKvleszB0yzIUBvM0MrS3b3GCBHnk2dlVjnRQ3Bt+k5kuMgxOFM1AW/MpqZJ62wFCYrlzywFHZxCiV8d2lxUZHQtINgcIZfvEWdQMdbP9i6RAJSRavtttc392GLc+7k2NB1QcoGJIzKvMYIouPnfwCOxOB+PQshJze1U5x/p/lRs0DYzB/EjDbRBZp2xo3MJdZBMLYH7gPVoSCGB+Hf9HJfQjPI3dDt6LVplwYw1KXp77qjsifej7y54AjZAC5ictxX50yGOgcJeRdv9VRiD9S/C5qbOtb5IyIlsiZ2yj+/4xArzlPkzr9aDzg09iaLjo+mvN1I7Xvy38o3PJ/cGFStKkjlKndeEMEDia8p8m2cN0ikyuHPBwBoL/59rihNSmIdsrbD7OwTl9wzgCQQ6rk6Viqe8Wzgr4Q9SVECpZjA5jJtfLDJHfByFXDCYaDbNSDZHnbmz69SAQ2UtP+1Q== jenkins@dstreambolt.click
```

## 📋 Step-by-Step: Add Deploy Key to GitHub

### Option 1: Add as Deploy Key (Recommended for single repo)

1. **Go to GitHub Repository Settings:**
   ```
   https://github.com/dstreambolt/dstream_cloud/settings/keys
   ```

2. **Click "Add deploy key"**

3. **Fill in the details:**
   - **Title:** `Jenkins DStreamBolt - DevOps Node`
   - **Key:** Paste the SSH public key above
   - ✅ **Allow write access** (if Jenkins needs to push)

4. **Click "Add key"**

### Option 2: Add as Personal SSH Key (For multiple repos)

1. **Go to GitHub SSH Keys Settings:**
   ```
   https://github.com/settings/keys
   ```

2. **Click "New SSH key"**

3. **Fill in the details:**
   - **Title:** `Jenkins DStreamBolt - DevOps Node`
   - **Key:** Paste the SSH public key above

4. **Click "Add SSH key"**

## 🔐 Add Credential to Jenkins

### Step 1: Access Jenkins

```bash
# Jenkins URL
http://13.235.238.208/jenkins
```

### Step 2: Navigate to Credentials

1. Click **"Manage Jenkins"** (left sidebar)
2. Click **"Credentials"**
3. Click **(global)** domain
4. Click **"Add Credentials"**

### Step 3: Configure SSH Credential

Fill in the form:

- **Kind:** `SSH Username with private key`
- **Scope:** `Global (Jenkins, nodes, items, all child items, etc)`
- **ID:** `jenkins-github-ssh`
- **Description:** `GitHub SSH Key for DStreamBolt Repository`
- **Username:** `git`
- **Private Key:** Select **"Enter directly"**
  - Click **"Add"**
  - Paste the private key from `/tmp/jenkins_github_private_key.pem`
  - Or get it from DevOps node:
    ```bash
    ssh -i ~/dstreambolt-access-key.pem ubuntu@13.235.238.208 \
      'sudo cat /var/lib/jenkins/.ssh/id_rsa'
    ```
- **Passphrase:** Leave empty (no passphrase)

Click **"Create"**

## ✅ Test GitHub Connection in Jenkins

### Method 1: Test in Jenkins Job Configuration

1. **Create a new Pipeline job:**
   - Click **"New Item"**
   - Enter name: `Test-GitHub-Connection`
   - Select: **"Pipeline"**
   - Click **"OK"**

2. **Configure Pipeline:**
   - Scroll to **"Pipeline"** section
   - **Definition:** `Pipeline script from SCM`
   - **SCM:** `Git`
   - **Repository URL:** `git@github.com:dstreambolt/dstream_cloud.git`
   - **Credentials:** Select `git (GitHub SSH Key for DStreamBolt Repository)`
   - **Branches to build:** `*/main` or `*/release/v1.0.0`

3. **Save and Build:**
   - Click **"Save"**
   - Click **"Build Now"**
   - Check console output

### Method 2: Test from DevOps Node

```bash
ssh -i ~/dstreambolt-access-key.pem ubuntu@13.235.238.208

# Test as jenkins user
sudo -u jenkins ssh -T git@github.com
# Expected output: "Hi dstreambolt! You've successfully authenticated..."

# Test git clone
sudo -u jenkins git clone git@github.com:dstreambolt/dstream_cloud.git /tmp/test-clone
```

## 📦 Update Existing Jenkins Jobs

Update the following jobs to use the new credential:

### 1. DStreamBolt-Deploy-Ingestion
```groovy
checkout([
    $class: 'GitSCM',
    branches: [[name: "*/${params.GIT_BRANCH}"]],
    userRemoteConfigs: [[
        url: 'git@github.com:dstreambolt/dstream_cloud.git',
        credentialsId: 'jenkins-github-ssh'  // ← Updated
    ]]
])
```

### 2. DStreamBolt-Deploy-Spark-Scala
```groovy
checkout([
    $class: 'GitSCM',
    branches: [[name: "*/${params.GIT_BRANCH}"]],
    userRemoteConfigs: [[
        url: 'git@github.com:dstreambolt/dstream_cloud.git',
        credentialsId: 'jenkins-github-ssh'  // ← Updated
    ]]
])
```

### 3. DStreamBolt-Log-Sender
```groovy
checkout([
    $class: 'GitSCM',
    branches: [[name: "*/main"]],
    userRemoteConfigs: [[
        url: 'git@github.com:dstreambolt/dstream_cloud.git',
        credentialsId: 'jenkins-github-ssh'  // ← Updated
    ]]
])
```

## 🔄 Quick Commands

### Get SSH Public Key
```bash
ssh -i ~/dstreambolt-access-key.pem ubuntu@13.235.238.208 \
  'sudo cat /var/lib/jenkins/.ssh/id_rsa.pub'
```

### Get SSH Private Key
```bash
ssh -i ~/dstreambolt-access-key.pem ubuntu@13.235.238.208 \
  'sudo cat /var/lib/jenkins/.ssh/id_rsa'
```

### Test GitHub Connection
```bash
ssh -i ~/dstreambolt-access-key.pem ubuntu@13.235.238.208 \
  'sudo -u jenkins ssh -T git@github.com'
```

### Regenerate SSH Key (if needed)
```bash
ssh -i ~/dstreambolt-access-key.pem ubuntu@13.235.238.208 << 'EOF'
sudo rm -f /var/lib/jenkins/.ssh/id_rsa*
sudo -u jenkins ssh-keygen -t rsa -b 4096 \
  -C "jenkins@dstreambolt.click" \
  -f /var/lib/jenkins/.ssh/id_rsa -N ""
sudo cat /var/lib/jenkins/.ssh/id_rsa.pub
EOF
```

## 🧪 Verify Setup Checklist

- [ ] SSH key added to GitHub (Deploy Key or Personal SSH Key)
- [ ] Credential added to Jenkins (ID: `jenkins-github-ssh`)
- [ ] Test GitHub connection from Jenkins
- [ ] Update existing Jenkins jobs to use new credential
- [ ] Test one pipeline job (run build)
- [ ] Verify clone/checkout works in console output

## 📊 Jenkins Job URLs

- **Jenkins Home:** http://13.235.238.208/jenkins
- **Credentials:** http://13.235.238.208/jenkins/credentials/
- **Deploy Ingestion:** http://13.235.238.208/jenkins/job/DStreamBolt-Deploy-Ingestion/
- **Deploy Spark:** http://13.235.238.208/jenkins/job/DStreamBolt-Deploy-Spark-Scala/
- **Log Sender:** http://13.235.238.208/jenkins/job/DStreamBolt-Log-Sender/

## 🔒 Security Notes

- ✅ Private key is stored only on Jenkins server (`/var/lib/jenkins/.ssh/id_rsa`)
- ✅ Private key is owned by `jenkins` user (chmod 600)
- ✅ SSH key is 4096-bit RSA (secure)
- ✅ No passphrase (for automation)
- ⚠️  If using Deploy Key, grant write access only if needed
- ⚠️  Rotate SSH keys periodically (every 90-180 days)

## 🛠️ Troubleshooting

### Issue: "Permission denied (publickey)"

**Solution 1:** Check if deploy key is added to GitHub
```bash
# Go to: https://github.com/dstreambolt/dstream_cloud/settings/keys
# Verify your key is listed
```

**Solution 2:** Test connection from Jenkins node
```bash
ssh -i ~/dstreambolt-access-key.pem ubuntu@13.235.238.208
sudo -u jenkins ssh -T git@github.com
```

### Issue: "Host key verification failed"

**Solution:** Add GitHub to known_hosts
```bash
ssh -i ~/dstreambolt-access-key.pem ubuntu@13.235.238.208
sudo -u jenkins ssh-keyscan -H github.com >> /var/lib/jenkins/.ssh/known_hosts
```

### Issue: Jenkins can't find credential

**Solution:** Check credential ID matches in Jenkinsfile
- Credential ID: `jenkins-github-ssh`
- Must match exactly in job configuration

### Issue: "Repository not found"

**Solution:** Check repository URL
- Correct: `git@github.com:dstreambolt/dstream_cloud.git`
- Wrong: `https://github.com/dstreambolt/dstream_cloud.git` (needs different auth)

## 📞 Need Help?

If you encounter issues:

1. Check Jenkins logs:
   ```bash
   ssh -i ~/dstreambolt-access-key.pem ubuntu@13.235.238.208
   sudo journalctl -u jenkins -n 100 --no-pager
   ```

2. Check job console output in Jenkins UI

3. Test GitHub connection manually as jenkins user

---

## ✅ Next Steps

1. **Add SSH key to GitHub** (see instructions above)
2. **Add credential to Jenkins** (see instructions above)
3. **Test connection** by running a Jenkins job
4. **Update all existing jobs** to use `jenkins-github-ssh` credential

**Setup complete! Jenkins can now access GitHub repositories. 🎉**

