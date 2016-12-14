import React from 'react'
import { Link } from 'react-router'
import { List } from 'semantic-ui-react'

import ListItem from './ListItem'
import { systemFunction as sF } from '../../../helpers/checkPermissions'
import styles from './styles'

export default class StatUnitsList extends React.Component {
  componentDidMount() {
    this.props.fetchStatUnits()
  }
  render() {
    const { statUnits, totalCount, totalPages, deleteStatUnit } = this.props
    return (
      <div>
        <h2>StatUnits list</h2>
        <div className={styles['list-root']}>
          {sF('StatUnitCreate') && <Link to="/statunits/create">Create</Link>}
          <List>
            {statUnits && statUnits.map(u =>
              <ListItem key={u.regId} {...u} deleteStatUnit={deleteStatUnit} />)}
          </List>
          <span>total: {totalCount}</span>
          <span>pages: {totalPages}</span>
        </div>
      </div>
    )
  }
}
