#!groovy
import groovy.json.JsonOutput

repoName = 'realm-js' // This is a global variable

def readGitTag() {
  sh "git describe --exact-match --tags HEAD | tail -n 1 > tag.txt 2>&1 || true"
  def tag = readFile('tag.txt').trim()
  return tag
}

def readGitSha() {
  sh "git rev-parse HEAD | cut -b1-8 > sha.txt"
  def sha = readFile('sha.txt').readLines().last().trim()
  return sha
}

def getVersion(){
  def dependencies = readProperties file: 'dependencies.list'
  def gitTag = readGitTag()
  def gitSha = readGitSha()
  if (gitTag == "") {
    return "${dependencies.VERSION}-g${gitSha}"
  }
  else {
    return dependencies.VERSION
  }
}

def setBuildName(newBuildName) {
  currentBuild.displayName = "${currentBuild.displayName} - ${newBuildName}"
}

def gitTag
def gitSha
def dependencies
def version

stage('check') {
  node('docker') {
    try {
      // - checkout the source
      for (i = 0; i < 3; i++) { // retry checkout up to three times to mitigate network and contention issues
        try {
          dir(env.WORKSPACE) {
            sshagent(['realm-ci-ssh']) {
              checkout([
                $class: 'GitSCM',
                branches: scm.branches,
                gitTool: 'native git',
                extensions: scm.extensions + [
                  [$class: 'CleanCheckout'],
                  [$class: 'SubmoduleOption', recursiveSubmodules: true]
                ],
                userRemoteConfigs: scm.userRemoteConfigs
              ])
            }
          }
          break
        } catch(Exception err) {
          if (i >= 2) {
            println("Checking out repository failed on attempt ${i + 1}, failing the build")
            throw err
          } else {
            println("Checking out repository failed on attempt ${i + 1}: " + err.toString())
          }
        }
      }
      
      stash name: 'inital checkout', useDefaultExcludes: false
      
      dependencies = readProperties file: 'dependencies.list'
  
      gitTag = readGitTag()
      gitSha = readGitSha()
      version = getVersion()
      echo "tag: ${gitTag}"
      if (gitTag == "") {
        echo "No tag given for this build"
        setBuildName("${gitSha}")
      } else {
        if (gitTag != "v${dependencies.VERSION}") {
          echo "Git tag '${gitTag}' does not match v${dependencies.VERSION}"
        } else {
          echo "Building release: '${gitTag}'"
          setBuildName("Tag ${gitTag}")
        }
      }
      echo "version: ${version}"
  
      if (['master'].contains(env.BRANCH_NAME)) {
        // If we're on master, instruct the docker image builds to push to the
        // cache registry
        env.DOCKER_PUSH = "1"
      }
    } finally {
      // delete the folder if working on a PR per realm/realm-js#734
      if (env.GIT_BRANCH.startsWith('PR-')) {
        dir(env.WORKSPACE) {
          deleteDir()
        }
      }
    }
  }
}

def reportStatus(target, state, message) {
  echo "Reporting Status ${state} to GitHub: " + ((message) ?: message.toString()).toString()
  if (message && message.length() > 140) {
    message = message.substring(0, 137) + '...' // GitHub API only allows for 140 characters
  }
  try {
    step([
      $class: 'GitHubCommitStatusSetter',
      contextSource: [$class: 'ManuallyEnteredCommitContextSource', context: target],
      statusResultSource: [$class: 'ConditionalStatusResultSource', results: [[
        $class: 'AnyBuildResult', message: message, state: state]]
      ],
      reposSource: [$class: 'ManuallyEnteredRepositorySource', url: 'https://github.com/realm/realm-js']
    ])
  } catch(Exception e) {
    echo "Error posting to GitHub: " + err.toString()
  }
}

def doInside(script, target, postStep = null) {
  try {
    reportStatus(target, 'PENDING', 'Build has started')
    
    // retry unstash up to three times to mitigate network and contention 
    for (i = 0; i < 3; i++) {
      try {
        dir(env.WORKSPACE) {
          deleteDir()
          unstash 'inital checkout'
        }
        break
      } catch(Exception err) {
        if (i >= 2) {
          println("Unstashing repository failed on attempt ${i + 1}, failing the build")
          throw err
        } else {
          println("Unstashing repository failed on attempt ${i + 1}: " + err.toString())
        }
      }
    }  
    
    sh "bash ${script} ${target}"
    if(postStep) {
       postStep.call()
    }

    reportStatus(target, 'SUCCESS', 'Success!')
  } catch(Exception e) {
  	reportStatus(target, 'FAILURE', e.toString())
    currentBuild.rawBuild.setResult(Result.FAILURE)
    e.printStackTrace()
    throw e
  } finally {
    dir(env.WORKSPACE) {
      deleteDir() // solving realm/realm-js#734
    }
  }
}

def doDockerInside(script, target, postStep = null) {
  docker.withRegistry("https://${env.DOCKER_REGISTRY}", "ecr:eu-west-1:aws-ci-user") {
    doInside(script, target, postStep)
  }
}

def doAndroidBuild(target, postStep = null) {
  return {
    node('docker && android') {
      lock("${env.NODE_NAME}-android") {
        doDockerInside("./scripts/docker-android-wrapper.sh ./scripts/test.sh", target, postStep)
      }
    }
  }
}

def doDockerBuild(target, postStep = null) {
  return {
    node('docker') {
      wrap([$class: 'AnsiColorBuildWrapper']) {
        doDockerInside("./scripts/docker-wrapper.sh ./scripts/test.sh", target, postStep)
      }
    }
  }
}

def doMacBuild(target, postStep = null) {
  return {
    node('osx_vegas') {
      wrap([$class: 'AnsiColorBuildWrapper']) {
        doInside("./scripts/test.sh", target, postStep)
      }
    }
  }
}

stage('build') {
  parallel(
    eslint: doDockerBuild('eslint-ci', {
      step([$class: 'CheckStylePublisher', canComputeNew: false, canRunOnFailed: true, defaultEncoding: '', healthy: '', pattern: 'eslint.xml', unHealthy: ''])
    }),
    jsdoc: doDockerBuild('jsdoc', {
      publishHTML([allowMissing: false, alwaysLinkToLastBuild: false, keepAll: false, reportDir: 'docs/output', reportFiles: 'index.html', reportName: 'Docs'])
    }),
    linux_node_debug: doDockerBuild('node Debug'),
    linux_node_release: doDockerBuild('node Release'),
    linux_test_runners: doDockerBuild('test-runners'),
    macos_node_debug: doMacBuild('node Debug'),
    macos_node_release: doMacBuild('node Release'),
    macos_realmjs_debug: doMacBuild('realmjs Debug'),
    macos_realmjs_release: doMacBuild('realmjs Release'),
    macos_react_tests_debug: doMacBuild('react-tests Debug'),
    macos_react_tests_release: doMacBuild('react-tests Release'),
    macos_react_example_debug: doMacBuild('react-example Debug'),
    macos_react_example_release: doMacBuild('react-example Release'),
    android_react_tests: doAndroidBuild('react-tests-android', {
      junit 'tests/react-test-app/tests.xml'
    })
  )
}