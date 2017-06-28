import React from 'react'
import { arrayOf, node, shape, string, func } from 'prop-types'
import { Menu, Header } from 'semantic-ui-react'
import { Link } from 'react-router'
import R from 'ramda'
import shouldUpdate from 'recompose/shouldUpdate'

import { wrapper } from 'helpers/locale'
import { systemFunction as sF } from 'helpers/checkPermissions'

export const linksView = 'links'
export const linksCreate = 'create'
export const linksDelete = 'delete'

const Layout = ({ children, localize, routes }) => {
  const route = R.findLast(v => v.path !== undefined, routes).path
  return (
    <div>
      <Header as="h2" dividing>{localize('LinkUnits')}</Header>
      <Menu pointing secondary>
        {sF('LinksView') &&
          <Menu.Item
            as={Link}
            to={`/statunits/${linksView}`}
            name={localize('LinkView')}
            active={route === linksView}
          />
        }
        {sF('LinksCreate') &&
          <Menu.Item
            as={Link}
            to={`/statunits/${linksView}/${linksCreate}`}
            name={localize('LinkCreate')}
            active={route === linksCreate}
          />
        }
        {sF('LinksDelete') &&
          <Menu.Item
            as={Link}
            to={`/statunits/${linksView}/${linksDelete}`}
            name={localize('LinkDelete')}
            active={route === linksDelete}
          />
        }
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
}

export const checkProps = (props, nextProps) =>
  nextProps.localize.lang !== props.localize.lang || !R.equals(nextProps.routes, props.routes)

export default wrapper(shouldUpdate(checkProps)(Layout))
