import React from 'react'
import { Link } from 'react-router'
import { Breadcrumb } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'
import styles from './styles'

const trimParams = path => path.indexOf('/:') === -1 ? path : path.match(/^.*(?=\/:)/)

const getUrl = sections => sections
  .reduce((prev, curr) => `${prev}/${curr.path}/`, '')
  .replace(/\/\/+/g, '/')

const Breadcrumbs = ({ routes, localize }) => {
  const sections = routes
    .filter(x => x.path !== undefined)
    .map(x => ({ ...x, path: trimParams(x.path) }))
    .reduce(
      (acc, curr, i, arr) => [
        ...acc,
        {
          key: curr.path,
          content: localize(`route_${curr.path === '/' ? 'home' : curr.path}`),
          ...(i < arr.length - 1
            ? { as: Link, to: getUrl([...arr.slice(0, i), curr]) }
            : { link: false }),
        },
      ],
      [],
    )
  return <Breadcrumb sections={sections} className={styles.breadcrumb} icon="right angle" />
}

const { func, shape, arrayOf, string } = React.PropTypes

Breadcrumbs.propTypes = {
  localize: func.isRequired,
  routes: arrayOf(shape({
    path: string,
  })).isRequired,
}

export default wrapper(Breadcrumbs)
