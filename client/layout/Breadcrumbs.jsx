import React from 'react'
import { connect } from 'react-redux'
import { func, shape, arrayOf, string } from 'prop-types'
import { Link } from 'react-router'
import { Breadcrumb } from 'semantic-ui-react'
import { equals, pipe } from 'ramda'
import { shouldUpdate } from 'recompose'

import { statUnitTypes } from 'helpers/enums'
import { getText } from 'helpers/locale'
import styles from './styles.pcss'

const getKey = (path, routerProps) => {
  if (routerProps.location.pathname.startsWith('/statunits/create/') && path === ':type') {
    return statUnitTypes.get(Number(routerProps.params.type))
  }
  if (path === '*') return 'route_notfound'
  if (path === '/') return 'route_home'
  if (path.includes('/')) return `route_${path.replace('/', '_')}`
  return `route_${path}`
}

const getUrl = sections =>
  sections.reduce((prev, curr) => `${prev}/${curr.path}/`, '').replace(/\/\/+/g, '/')

const Breadcrumbs = ({ routerProps, localize }) => {
  const sections = routerProps.routes
    .filter(x => x.path !== undefined)
    .map((x) => {
      const match = x.path.indexOf('/:') === -1 ? x.path : x.path.match(/[^/:]*/)
      const path = typeof match === 'string' ? match : match[0]
      return { ...x, path }
    })
    .reduce(
      (acc, curr, i, arr) => [
        ...acc,
        {
          key: curr.path,
          content: localize(getKey(curr.path, routerProps)),
          ...(i < arr.length - 1
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

Breadcrumbs.propTypes = {
  localize: func.isRequired,
  routerProps: routerPropTypes.isRequired,
}

const checkProps = (props, nextProps) =>
  nextProps.localize.lang !== props.localize.lang ||
  !equals(nextProps.routerProps, props.routerProps)

const mapStateToProps = (state, props) => ({
  ...props,
  localize: getText(state.locale),
})

const enhance = pipe(shouldUpdate(checkProps), connect(mapStateToProps))

export default enhance(Breadcrumbs)
