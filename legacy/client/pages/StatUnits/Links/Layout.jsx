import React from 'react'
import { arrayOf, node, shape, string, func } from 'prop-types'
import { Menu, Header } from 'semantic-ui-react'
import { Link } from 'react-router'
import { findLast, equals, pipe } from 'ramda'
import shouldUpdate from 'recompose/shouldUpdate'

import { withLocalizeNaive } from '/helpers/locale'
import { checkSystemFunction as sF } from '/helpers/config'

export const linksView = 'links'
export const linksCreate = 'create'
export const linksDelete = 'delete'

const Layout = (props) => {
  const {
    children,
    localize,
    routes,
    location: { search },
  } = props
  const route = findLast(v => v.path !== undefined, routes).path
  return (
    <div>
      <Header as="h2" dividing>
        {localize('LinkUnits')}
      </Header>
      <Menu pointing secondary>
        {sF('LinksView') && (
          <Menu.Item
            as={Link}
            to={`/statunits/${linksView}${search}`}
            name={localize('LinkView')}
            active={route === linksView}
          />
        )}
        {sF('LinksCreate') && (
          <Menu.Item
            as={Link}
            to={`/statunits/${linksView}/${linksCreate}${search}`}
            name={localize('LinkCreate')}
            active={route === linksCreate}
          />
        )}
        {sF('LinksDelete') && (
          <Menu.Item
            as={Link}
            to={`/statunits/${linksView}/${linksDelete}${search}`}
            name={localize('LinkDelete')}
            active={route === linksDelete}
          />
        )}
      </Menu>
      {children}
    </div>
  )
}

Layout.propTypes = {
  children: node.isRequired,
  localize: func.isRequired,
  routes: arrayOf(shape({
    path: string,
  })).isRequired,
  location: shape({
    search: string,
  }).isRequired,
}

export const checkProps = (props, nextProps) =>
  nextProps.localize.lang !== props.localize.lang ||
  !equals(nextProps.routes, props.routes) ||
  !equals(nextProps.location, props.location)

export default pipe(shouldUpdate(checkProps), withLocalizeNaive)(Layout)
