import React from 'react'
import { connect } from 'react-redux'
import { func, shape, arrayOf, string } from 'prop-types'
import { Link } from 'react-router'
import { Breadcrumb } from 'semantic-ui-react'
import { equals, pipe } from 'ramda'
import { shouldUpdate } from 'recompose'

import { statUnitTypes } from 'helpers/enums.js'
import { getText } from 'helpers/locale.js'
import styles from '../styles.scss'

const getKey = (path, routerProps) => {
  if (routerProps.location.pathname.startsWith('/statunits/create/') && path === 'type') {
    return statUnitTypes.get(Number(routerProps.params.type))
  }
  if (path === '*') return 'route_notfound'
  if (path === '/') return 'route_home'
  if (path.includes('/')) return `route_${path.replace(/\//g, '_')}`
  return `route_${path}`
}

const getUrl = sections =>
  sections.reduce((prev, curr) => `${prev}/${curr.path}`, '').replace(/\/\/+/g, '/')

const isFromSearchPage = (previousRoute, { location: { pathname } }) =>
  previousRoute && previousRoute.pathname === '/' && pathname.startsWith('/statunits')

const Breadcrumbs = ({ routerProps, localize, previousRoute }) => {
  const sections = routerProps.routes
    .filter(x => x.path !== undefined)
    .map((x) => {
      const match =
        x.path.indexOf('/:') === -1
          ? x.path.indexOf(':') === -1
            ? x.path
            : x.path.replace(/:/g, '')
          : x.path.indexOf(':') === -1
            ? x.path.match(/[^/:]*/)
            : x.path.replace(/:/g, '')
      const path = typeof match === 'string' ? match : match[0]
      return { ...x, path }
    })
    .reduce(
      (acc, curr, i, arr) => [
        ...acc,
        {
          key: curr.path,
          content: localize(getKey(curr.path, routerProps)),
          ...(i === arr.length - 2 && isFromSearchPage(previousRoute, routerProps)
            ? { as: Link, to: `${previousRoute.pathname}${previousRoute.search}` }
            : i < arr.length - 1
              ? { as: Link, to: getUrl([...arr.slice(0, i), curr]) }
              : { link: false }),
        },
      ],
      [],
    )
  return (
    <Breadcrumb
      sections={sections.length === 1 ? [] : sections}
      className={styles.breadcrumb}
      icon="right angle"
    />
  )
}

export const routerPropTypes = shape({
  routes: arrayOf(shape({
    path: string,
  })).isRequired,
  location: shape({
    pathname: string.isRequired,
  }).isRequired,
  params: shape({}).isRequired,
})

Breadcrumbs.defaultProps = {
  previousRoute: undefined,
}

Breadcrumbs.propTypes = {
  localize: func.isRequired,
  routerProps: routerPropTypes.isRequired,
  previousRoute: shape({}),
}

const checkProps = (props, nextProps) =>
  nextProps.localize.lang !== props.localize.lang ||
  !equals(nextProps.routerProps, props.routerProps) ||
  !equals(nextProps.previousRoute, props.previousRoute)

const mapStateToProps = (state, props) => ({
  ...props,
  localize: getText(state.locale),
})

const enhance = pipe(shouldUpdate(checkProps), connect(mapStateToProps))

export default enhance(Breadcrumbs)
