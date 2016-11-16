/* eslint-disable global-require, no-console, import/newline-after-import */
const fs = require('fs')
const del = require('del')
const cpy = require('cpy')
const path = require('path')
const mkdirp = require('mkdirp')
const webpack = require('webpack')
const cp = require('child_process')

const tasks = new Map()

function run(task) {
  const start = new Date()
  console.log(`Starting '${task}'...`)
  return Promise.resolve().then(() => tasks.get(task)()).then(() => {
    console.log(`Finished '${task}' after ${new Date().getTime() - start.getTime()}ms`)
  }, err => console.error(err.stack))
}

// Clean up the output directory
tasks.set('clean', () => Promise.resolve()
  .then(() => del(['build/*', 'nscreg.Server/wwwroot/dist/*', '!build/.git'], { dot: true }))
  .then(() => {
    // mkdirp.sync('build/public/dist')
    mkdirp.sync('nscreg.Server/wwwroot/dist')
  }))

// Bundle JavaScript, CSS and image files with Webpack
tasks.set('bundle', () => {
  const webpackConfig = require('./webpack.config')
  return new Promise((resolve, reject) => {
    webpack(webpackConfig).run((err, stats) => {
      if (err) {
        reject(err)
      } else {
        console.log(stats.toString(webpackConfig.stats))
        resolve()
      }
    })
  })
})

// Copy static files into the output folder
tasks.set('copy', () => cpy(['nscreg.Server/wwwroot/**/*.*'], 'build', { parents: true }))

// Copy ASP.NET application config file for production and development environments
tasks.set('appSettings', () => new Promise((resolve) => {
  const environments = ['Production', 'Development']
  let count = environments.length
  const source = require('./nscreg.Server/appSettings.json')
  delete source.Logging
  environments.forEach((env) => {
    const filename = path.resolve(__dirname, `./nscreg.Server/appSettings.${env}.json`)
    try {
      fs.writeFileSync(filename, JSON.stringify(source, null, '  '), { flag: 'wx' })
    } catch (err) {} // eslint-disable-line no-empty
    if (--count === 0) resolve()
  })
}))

// Copy static files into the output folder
tasks.set('build', () => {
  global.DEBUG = process.argv.includes('--debug') || false
  return Promise.resolve()
    .then(() => run('clean'))
    .then(() => run('bundle'))
    // .then(() => run('copy'))
    .then(() => run('appSettings'))
    .then(() => new Promise((resolve, reject) => {
      const options = { stdio: ['ignore', 'inherit', 'inherit'] }
      const config = global.DEBUG ? 'Debug' : 'Release'
      const args = ['publish', 'nscreg.Server', '-o', 'build', '-c', config, '-r', 'coreclr']
      cp.spawn('dotnet', args, options).on('close', (code) => {
        if (code === 0) {
          resolve()
        } else {
          reject(new Error(`dotnet ${args.join(' ')} => ${code} (error)`))
        }
      })
    }))
})

// Build website and launch it in a browser for testing in watch mode
tasks.set('start', () => {
  global.HMR = !process.argv.includes('--no-hmr') // Hot Module Replacement (HMR)
  return Promise.resolve()
    .then(() => run('clean'))
    .then(() => run('appSettings'))
    .then(() => new Promise((resolve) => {
      let count = 0
      const webpackConfig = require('./webpack.config')
      const compiler = webpack(webpackConfig)
      // Node.js middleware that compiles application in watch mode with HMR support
      const webpackDevMiddleware = require('webpack-dev-middleware')(compiler, {
        publicPath: webpackConfig.output.publicPath,
        stats: webpackConfig.stats,
      })
      compiler.plugin('done', () => {
        // Launch ASP.NET Core server after the initial bundling is complete
        if (++count === 1) {
          const options = {
            cwd: path.resolve(__dirname, './nscreg.Server/'),
            stdio: ['ignore', 'pipe', 'inherit'],
            env: Object.assign({}, process.env, {
              ASPNETCORE_ENVIRONMENT: 'Development',
            }),
          }
          cp.spawn('dotnet', ['watch', 'run'], options).stdout.on('data', (data) => {
            process.stdout.write(data)
            if (data.indexOf('Application started.') !== -1) {
              // Launch Browsersync after the initial bundling is complete
              require('browser-sync').create().init({
                proxy: {
                  target: 'localhost:5000',
                  middleware: [
                    webpackDevMiddleware,
                    require('webpack-hot-middleware')(compiler),
                  ],
                },
              }, resolve)
            }
          })
        }
      })
    }))
})

// Execute the specified task or default one. E.g.: node run build
run(/^\w/.test(process.argv[2] || '') ? process.argv[2] : 'start' /* default */)
