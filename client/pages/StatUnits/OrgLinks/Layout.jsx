import React from 'react'
import { Header } from 'semantic-ui-react'
import R from 'ramda'
import shouldUpdate from 'recompose/shouldUpdate'

import { wrapper } from 'helpers/locale'

export const OrgLinksView = 'Orglinks'

const Layout = ({ children, localize }) => {
  return (
    <div>
      <Header as="h2" dividing>{localize('Orglinks')}</Header>
      {children}
    </div>
  )
}

const { arrayOf, node, shape, string, func } = React.PropTypes
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
