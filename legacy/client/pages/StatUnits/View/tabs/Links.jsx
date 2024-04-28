import React from 'react'
import { func, shape, oneOfType, number, string } from 'prop-types'
import { Segment, Header } from 'semantic-ui-react'

import LinksTree from '../../Links/Components/LinksTree/index.js'
import styles from './styles.scss'

const Links = ({ filter, fetchData, localize, activeTab }) => (
  <div>
    {activeTab !== 'links' && (
      <Header as="h5" className={styles.heigthHeader} content={localize('Links')} />
    )}
    <Segment>
      <LinksTree filter={filter} getUnitsTree={fetchData} localize={localize} />
    </Segment>
  </div>
)

Links.propTypes = {
  filter: shape({
    id: oneOfType([number, string]).isRequired,
    type: oneOfType([number, string]).isRequired,
  }).isRequired,
  fetchData: func.isRequired,
  localize: func.isRequired,
  activeTab: string.isRequired,
}

export default Links
