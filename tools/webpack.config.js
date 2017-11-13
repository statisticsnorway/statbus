/* eslint-disable global-require */
const Path = require('path')
const Webpack = require('webpack')
const AssetsWebpackPlugin = require('assets-webpack-plugin')

const pkg = require('../package.json')
const appConfig = require('../appsettings.json')

const isDebug = global.DEBUG === false ? false : !process.argv.includes('--release')
const isVerbose = process.argv.includes('--verbose') || process.argv.includes('-v')
const useHMR = !!global.HMR
const babelConfig = Object.assign({}, pkg.babel, {
  babelrc: false,
  cacheDirectory: useHMR,
})

const config = {
  context: Path.resolve(__dirname, '../client'),
  entry: ['./index.js'],
  output: {
    path: Path.resolve(__dirname, '../src/nscreg.Server/wwwroot/dist'),
    publicPath: '/dist/',
    filename: isDebug ? '[name].js?[hash]' : '[name].[hash].js',
    chunkFilename: isDebug ? '[id].js?[chunkhash]' : '[id].[chunkhash].js',
    sourcePrefix: '  ',
  },
  devtool: isDebug ? 'source-map' : false,
  performance: {
    hints: isDebug ? false : 'warning',
  },
  stats: {
    cached: isVerbose,
    cachedAssets: isVerbose,
    chunkModules: isVerbose,
    chunks: isVerbose,
    colors: true,
    hash: isVerbose,
    timings: true,
    version: isVerbose,
  },
  plugins: [
    new Webpack.optimize.OccurrenceOrderPlugin(),
    new Webpack.DefinePlugin({
      'process.env.NODE_ENV': isDebug ? '"development"' : '"production"',
      __DEV__: isDebug,
    }),
    new AssetsWebpackPlugin({
      path: Path.resolve(__dirname, '../src/nscreg.Server/wwwroot/dist'),
      filename: 'assets.json',
      prettyPrint: true,
    }),
    new Webpack.ContextReplacementPlugin(
      /moment[/\\]locale$/,
      new RegExp(appConfig.LocalizationSettings.Locales.map(x => x.Key.substr(0, 2)).join('|')),
    ),
  ],
  module: {
    rules: [
      {
        test: /\.jsx?$/,
        include: [Path.resolve(__dirname, '../client')],
        use: {
          loader: 'babel-loader',
          options: babelConfig,
        },
      },
      {
        test: /\.pcss/,
        use: [
          'style-loader',
          {
            loader: 'css-loader',
            options: {
              sourceMap: isDebug,
              modules: true,
              localIdentName: isDebug ? '[name]_[local]_[hash:base64:3]' : '[hash:base64:4]',
              minimize: !isDebug,
            },
          },
          'postcss-loader',
        ],
      },
    ],
  },
  resolve: {
    alias: {
      components: Path.resolve(__dirname, './client/components'),
      helpers: Path.resolve(__dirname, './client/helpers'),
      layout: Path.resolve(__dirname, './client/layout'),
      pages: Path.resolve(__dirname, './client/pages'),
    },
    extensions: ['.js', '.jsx', '.pcss'],
  },
}

if (!isDebug) {
  config.plugins = [
    ...config.plugins,
    new Webpack.optimize.ModuleConcatenationPlugin(),
    new Webpack.optimize.UglifyJsPlugin({ compress: { warnings: isVerbose } }),
    new Webpack.optimize.AggressiveMergingPlugin(),
  ]
}

if (isDebug && useHMR) {
  babelConfig.plugins = ['react-hot-loader/babel', ...babelConfig.plugins]
  config.entry = [
    'react-hot-loader/patch',
    'webpack-hot-middleware/client',
    'eventsource-polyfill',
    ...config.entry,
  ]
  config.plugins = [
    ...config.plugins,
    new Webpack.HotModuleReplacementPlugin(),
    new Webpack.NoEmitOnErrorsPlugin(),
  ]
}

module.exports = config
