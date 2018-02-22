import React from 'react'
import { shape, func, arrayOf, string } from 'prop-types'
import { Header } from 'semantic-ui-react'

import { ActivitiesField } from 'components/fields'
import styles from './styles.pcss'

const Activity = ({ data, localize, activeTab }) => (
  <div>
    {activeTab !== 'activity' && (
      <Header as="h5" className={styles.heigthHeader} content={localize('Activity')} />
    )}
    <ActivitiesField name="activities" value={data} localize={localize} readOnly />
  </div>
)

Activity.propTypes = {
  data: arrayOf(shape({})),
  localize: func.isRequired,
  activeTab: string.isRequired,
}

Activity.defaultProps = {
  data: undefined,
}

export default Activity
