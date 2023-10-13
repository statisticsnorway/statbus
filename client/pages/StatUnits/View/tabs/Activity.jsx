import React from 'react'
import { shape, func, arrayOf, string } from 'prop-types'
import { Header } from 'semantic-ui-react'
import { ActivitiesList } from '/client/components/fields'
import styles from './styles.scss'

class Activity extends React.Component {
  constructor(props) {
    super(props)
    this.state = {
      data: props.data || [], // Initialize the data state with props or an empty array
    }
  }

  render() {
    const { localize, activeTab } = this.props
    const { data } = this.state

    return (
      <div>
        {activeTab !== 'activity' && (
          <Header as="h5" className={styles.heigthHeader} content={localize('Activity')} />
        )}
        <ActivitiesList name="activities" value={data} localize={localize} readOnly />
      </div>
    )
  }
}

Activity.propTypes = {
  data: arrayOf(shape({})),
  localize: func.isRequired,
  activeTab: string.isRequired,
}

Activity.defaultProps = {
  data: undefined,
}

export default Activity
