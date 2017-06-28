import React from 'react'
import { func, shape, arrayOf, string } from 'prop-types'
import { Link } from 'react-router'
import { Breadcrumb } from 'semantic-ui-react'
import R from 'ramda'
import shouldUpdate from 'recompose/shouldUpdate'

import { wrapper } from 'helpers/locale'
import styles from './styles.pcss'

const trimParams = path => path.indexOf('/:') === -1 ? path : path.match(/[^/:]*/)

const getKey = path => path === '/' ? 'home' : path === '*' ? 'notfound' : path

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
          content: localize(`route_${getKey(curr.path)}`),
          ...(i < arr.length - 1
            ? { as: Link, to: getUrl([...arr.slice(0, i), curr]) }
            : { link: false }),
        },
      ],
      [],
    )
  return <Breadcrumb sections={sections} className={styles.breadcrumb} icon="right angle" />
}

Breadcrumbs.propTypes = {
  localize: func.isRequired,
  routes: arrayOf(shape({
    path: string,
  })).isRequired,
}

export const checkProps = (props, nextProps) =>
  nextProps.localize.lang !== props.localize.lang ||
  !R.equals(nextProps.routes, props.routes)

export default wrapper(shouldUpdate(checkProps)(Breadcrumbs))
