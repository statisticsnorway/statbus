/* eslint-disable global-require, no-console, import/newline-after-import */
const cp = require('child_process')
const cpy = require('cpy')
const copyDir = require('copy-dir')
const del = require('del')
const fs = require('fs')
const mkdirp = require('mkdirp')
const path = require('path')
const webpack = require('webpack')

const tasks = new Map()

function run(taskName) {
  const task = tasks.get(taskName)
  const start = new Date()
  console.log(`Starting '${taskName}'...`)
  return Promise.resolve()
    .then(task)
    .then(
      () => console.log(`Finished '${taskName}' after ${new Date().getTime() - start.getTime()}ms`),
      err => console.error(err.stack),
    )
}

// Clean up the output directory
tasks.set('clean', () =>
  Promise.resolve()
    .then(() =>
      del(['./build/*', './src/nscreg.Server/wwwroot/dist/*', '!./build/.git'], { dot: true }))
    .then(() => mkdirp.sync('./src/nscreg.Server/wwwroot/dist')))

// Copy vendor bundles (styles, scripts, fonts, etc.)
tasks.set('copy', () =>
  Promise.resolve()
    // Semantic-UI css
    .then(() =>
      cpy('./node_modules/semantic-ui-css/semantic.min.css', './src/nscreg.Server/wwwroot'))
    .then(() =>
      copyDir.sync('./node_modules/semantic-ui-css/themes', './src/nscreg.Server/wwwroot/themes'))
    // ant.design tree css
    .then(() =>
      cpy('./node_modules/antd/lib/tree/style/index.css', './src/nscreg.Server/wwwroot', {
        rename: 'antd-tree.css',
      }))
    // react-datepicker css
    .then(() =>
      cpy(
        './node_modules/react-datepicker/dist/react-datepicker.min.css',
        './src/nscreg.Server/wwwroot',
      ))
    // react-select css
    .then(() =>
      cpy('./node_modules/react-select/dist/react-select.min.css', './src/nscreg.Server/wwwroot')))

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

// Copy ASP.NET application config file for production and development environments
tasks.set(
  'appsettings',
  () =>
    new Promise((resolve) => {
      const environments = ['Production', 'Development']
      let count = environments.length
      const rootCfg = require('../appsettings.json')
      let localCfg
      try {
        // eslint-disable-next-line import/no-unresolved
        localCfg = require('../src/nscreg.Server/appsettings.json')
      } catch (err) {
        localCfg = {}
      }
      const source = { ...rootCfg, ...localCfg }
      delete source.Logging
      environments.forEach((env) => {
        const filename = path.resolve(__dirname, `../src/nscreg.Server/appsettings.${env}.json`)
        try {
          fs.writeFileSync(filename, JSON.stringify(source, null, '  '), { flag: 'wx' })
        } catch (err) {} // eslint-disable-line no-empty
        if (--count === 0) resolve()
      })
    }),
)

// Copy static files into the output folder
tasks.set('build', () => {
  global.DEBUG = process.argv.includes('--debug') || false
  return Promise.resolve()
    .then(() => run('clean'))
    .then(() => run('copy'))
    .then(() => run('bundle'))
    .then(() => run('appsettings'))
    .then(() =>
      new Promise((resolve, reject) => {
        const options = { stdio: ['ignore', 'inherit', 'inherit'] }
        const config = global.DEBUG ? 'Debug' : 'Release'
        const args = [
          'publish',
          path.resolve(__dirname, '../src/nscreg.Server'),
          '-o',
          path.resolve(__dirname, '../build'),
          '-f',
          'netcoreapp1.1',
          '-c',
          config,
        ]
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
    .then(() => run('copy'))
    .then(() => run('appsettings'))
    .then(() =>
      new Promise((resolve) => {
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
              cwd: path.resolve(__dirname, '../src/nscreg.Server/'),
              stdio: ['ignore', 'pipe', 'inherit'],
              env: { ...process.env, ASPNETCORE_ENVIRONMENT: 'Development' },
            }
            cp.spawn('dotnet', ['watch', 'run'], options).stdout.on('data', (data) => {
              process.stdout.write(data)
              if (data.indexOf('Application started.') !== -1) {
                // Launch Browsersync after the initial bundling is complete
                require('browser-sync')
                  .create()
                  .init(
                    {
                      proxy: {
                        target: 'localhost:5000',
                        middleware: [
                          webpackDevMiddleware,
                          require('webpack-hot-middleware')(compiler),
                        ],
                      },
                    },
                    resolve,
                  )
              }
            })
          }
        })
      }))
})

// Execute the specified task or default one. E.g.: node run build
run(/^\w/.test(process.argv[2] || '') ? process.argv[2] : 'start' /* default */)
