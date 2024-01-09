import React from 'react'
import { Container, Header, Button, Icon } from 'semantic-ui-react'
import PropTypes from 'prop-types'

import ReportsTree from './ReportsTree.jsx'

const Reports = props => (
  <Container fluid>
    <Header as="h2">{props.localize('Reports')}</Header>
    <ReportsTree dataTree={props.reportsTree} />
    <Button
      content={props.localize('Back')}
      onClick={props.navigateBack}
      icon={<Icon size="large" name="chevron left" />}
      size="small"
      color="grey"
      type="button"
    />
  </Container>
)

Reports.propTypes = {
  reportsTree: PropTypes.arrayOf(PropTypes.shape({})).isRequired,
  navigateBack: PropTypes.func.isRequired,
  localize: PropTypes.func.isRequired,
}

export default Reports
