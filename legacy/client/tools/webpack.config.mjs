import Path from 'path';
import Webpack from 'webpack';
import AssetsWebpackPlugin from 'assets-webpack-plugin';
import { fileURLToPath } from 'url';
import { promises as fs } from 'fs';

const pkg = JSON.parse(await fs.readFile('./package.json', 'utf-8'));
const appConfig = JSON.parse(await fs.readFile('./appsettings.Shared.json', 'utf-8'));

const __filename = fileURLToPath(import.meta.url);
const __dirname = Path.dirname(__filename);

const isDebug = global.DEBUG === false ? false : !process.argv.includes('--release');
const isVerbose = process.argv.includes('--verbose') || process.argv.includes('-v');
const useHMR = !!global.HMR;
const babelConfig = { ...pkg.babel, babelrc: false, cacheDirectory: useHMR };

const config = {
  context: Path.resolve(__dirname, '..'),
  entry: ['./styles.scss', './index.js'],
  output: {
    path: Path.resolve(__dirname, '../../src/nscreg.Server/wwwroot'),
    publicPath: '/',
    filename: isDebug ? '[name].js?[hash]' : '[name].[hash].js',
    chunkFilename: isDebug ? '[id].js?[chunkhash]' : '[id].[chunkhash].js',
    sourcePrefix: '  ',
  },
  devtool: isDebug ? 'source-map' : false,
  performance: {
    hints: false,
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
    new AssetsWebpackPlugin({
      path: Path.resolve(__dirname, '../../src/nscreg.Server/wwwroot'),
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
        include: [Path.resolve(__dirname, '..')],
        use: {
          loader: 'babel-loader',
          options: babelConfig,
        },
      },
      {
        test: /\.scss/,
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
          'sass-loader',
        ],
      },
      {
        test: /\.css$/i,
        use: ['style-loader', 'css-loader'],
      },
    ],
  },
  resolve: {
    alias: {
      components: Path.resolve(__dirname, './components'),
      helpers: Path.resolve(__dirname, './helpers'),
      layout: Path.resolve(__dirname, './layout'),
      pages: Path.resolve(__dirname, './pages'),
    },
    extensions: ['.js', '.jsx', '.scss'],
  },
}

if (!isDebug) {
  config.plugins = [...config.plugins, new Webpack.optimize.AggressiveMergingPlugin()]
  config.mode = 'production'
} else {
  config.mode = 'development'
}

if (isDebug && useHMR) {
  babelConfig.plugins = ['react-hot-loader/babel', ...babelConfig.plugins]
  config.entry = [
    'react-hot-loader/patch',
    'webpack-hot-middleware/client',
    'eventsource-polyfill',
    ...config.entry,
  ]
  config.plugins = [...config.plugins, new Webpack.HotModuleReplacementPlugin()]
  config.mode = 'development'
}


export default config;
