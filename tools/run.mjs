/* eslint-disable global-require, no-console, import/newline-after-import */
import { spawn } from 'child_process';
import cpy from 'cpy';
import copyDir from 'copy-dir';
import del from 'del';
import { writeFileSync } from 'fs';
import mkdirp from 'mkdirp';
import path from 'path';
import webpack from 'webpack';
import browsersync from 'browser-sync';
import config from './webpack.config.mjs';
import { default as webpackConfig } from './webpack.config.mjs';
import { fileURLToPath } from 'url';
import webpackDevMiddlewarePackage from 'webpack-dev-middleware';
import webpackHotMiddleware from 'webpack-hot-middleware';
import fs from 'fs';


const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const tasks = new Map();

function run(taskName) {
  const task = tasks.get(taskName);
  const start = new Date();
  console.log(`Starting '${taskName}'...`);
  return Promise.resolve()
    .then(task)
    .then(
      () => console.log(`Finished '${taskName}' after ${new Date().getTime() - start.getTime()}ms`),
      err => console.error(err.stack),
    );
}


// Clean up the output directory
tasks.set('clean', () =>
  Promise.resolve()
    .then(() =>
      del(
        [
          './build/*',
          './src/nscreg.Server/wwwroot/dist/*',
          '!./build/.git',
          './src/nscreg.Server/wwwroot/semantic.min.css',
          './src/nscreg.Server/wwwroot/themes',
          './src/nscreg.Server/wwwroot/antd-tree.css',
          './src/nscreg.Server/wwwroot/react-datepicker.min.css',
          './src/nscreg.Server/wwwroot/react-select.min.css',
        ],
        { dot: true },
      ))
    .then(() => mkdirp.sync('./src/nscreg.Server/wwwroot/dist')))


// Copy vendor bundles (styles, scripts, fonts, etc.)
const copyTasks = [
  {
    src: './node_modules/semantic-ui-css/semantic.min.css',
    dest: './src/nscreg.Server/wwwroot',
    message: "Copying semantic.min.css...",
    rename: undefined,
  },
  {
    src: './node_modules/semantic-ui-css/themes',
    dest: './src/nscreg.Server/wwwroot/themes',
    message: "Copying themes...",
    isSync: true,
  },
  {
    src: './node_modules/antd/lib/tree/style/index.css',
    dest: './src/nscreg.Server/wwwroot',
    message: "Copying antd-tree.css...",
    rename: 'antd-tree.css',
  },
  {
    src: './node_modules/react-datepicker/dist/react-datepicker.min.css',
    dest: './src/nscreg.Server/wwwroot',
    message: "Copying react-datepicker.min.css...",
    rename: undefined,
  },
  {
    src: './node_modules/react-select/dist/react-select.min.css',
    dest: './src/nscreg.Server/wwwroot',
    message: "Copying react-select.min.css...",
    rename: undefined,
  },
];

tasks.set('copy', async () => {
  try {
    for (const task of copyTasks) {
      console.log(task.message);
      if (task.isSync) {
        try {
          copyDir.sync(task.src, task.dest);
          console.log(`Copied successfully: ${task.src}`);
        } catch (error) {
          console.error(`Error copying: ${task.src}`, error);
        }
      } else {
        try {
          var cpyOptions = { flat: true };
          if ( task.rename )
           cpyOptions["rename"] = task.rename;
          var destination = await cpy(task.src, task.dest, cpyOptions)
          console.log(`Copied ${task.src} to ${destination} successfully`);
        } catch (error) {
          console.error(`Error copying: ${task.src}`, error);
        }
      }
    }
  } catch (error) {
    console.error("Error in copy task:", error);
  }
});


// Bundle JavaScript, CSS and image files with Webpack
tasks.set('bundle', () => {
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


tasks.set(
  'appsettings',
  () =>
    new Promise(async (resolve) => {
      const environments = ['Production', 'Development'];
      let count = environments.length;

      try {
        // Use fs.promises to read JSON files
        const rootCfg = JSON.parse(await fs.readFile('../appsettings.Shared.json', 'utf8'));
        let localCfg;

        try {
          localCfg = JSON.parse(await fs.readFile('../src/nscreg.Server/appsettings.json', 'utf8'));
        } catch (err) {
          localCfg = {};
        }

        const source = { ...rootCfg, ...localCfg };
        environments.forEach((env) => {
          const filename = path.resolve(process.cwd(), `../src/nscreg.Server/appsettings.${env}.json`);
          try {
            fs.writeFileSync(filename, JSON.stringify(source, null, '  '), { flag: 'wx' });
          } catch (err) {
            // handle error
          }

          if (--count === 0) resolve();
        });
      } catch (error) {
        console.error('Error loading config files:', error);
      }
    })
);


// Copy static files into the output folder
tasks.set('build', () => {
  global.DEBUG = process.argv.includes('--debug') || false
  return Promise.resolve()
    .then(() => run('clean'))
    .then(() => run('copy'))
    .then(() => run('bundle'))
    .then(() => run('appsettings'))
  // .then(() =>
  //   new Promise((resolve, reject) => {
  //     const options = { stdio: ['ignore', 'inherit', 'inherit'] }
  //     const config = global.DEBUG ? 'Debug' : 'Release'
  //     const args = [
  //       'publish',
  //       path.resolve(__dirname, '../src/nscreg.Server'),
  //       '-o',
  //       path.resolve(__dirname, '../build'),
  //       '-f',
  //       'netcoreapp3.1',
  //       '-c',
  //       config,
  //     ]
  //     cp.spawn('dotnet', args, options).on('close', (code) => {
  //       if (code === 0) {
  //         resolve()
  //       } else {
  //         reject(new Error(`dotnet ${args.join(' ')} => ${code} (error)`))
  //       }
  //     })
  //   }))
})


tasks.set('watch', async () => {
  global.HMR = !process.argv.includes('--no-hmr'); // Hot Module Replacement (HMR)
  try {
    await run('clean');
    await run('copy');

    const compiler = webpack(webpackConfig);

    // Set up a watcher to rebuild when files change
    await new Promise((resolve, reject) => {
      const watcher = compiler.watch({}, (err, stats) => {
        if (err) {
          console.error(err);
          reject(err);
        } else {
          console.log(stats.toString({ colors: true }));
        }
      });

      process.on('SIGINT', () => {
        watcher.close(() => {
          console.log('Stopping webpack watch...');
          resolve();
          process.exit(0);
        });
      });
    });
  } catch (error) {
    console.error(error);
  }
});



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


export { run };
