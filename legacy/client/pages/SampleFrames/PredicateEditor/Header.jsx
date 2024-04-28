import React from 'react'
import PropTypes from 'prop-types'
import { Table, Icon } from 'semantic-ui-react'
import InsertButton from './InsertButton.jsx'
import styles from './styles.scss'

function Header(props) {
  const { maxShift, canGroup, anySelected, group, toggleAll, onInsert, localize } = props

  return (
    <Table.Header>
      <Table.Row>
        <Table.HeaderCell textAlign="right" colSpan={maxShift + 1} collapsing>
          <Icon.Group
            onClick={canGroup ? group : undefined}
            title={localize('GroupSelectedClauses')}
            className="cursor-pointer"
            size="large"
          >
            <Icon name="sitemap" disabled={!canGroup} className={styles['rotated-270']} />
            <Icon
              name="add"
              disabled={!canGroup}
              className={styles['large-corner-icon']}
              color="green"
              corner
            />
          </Icon.Group>
          &nbsp;
          <Icon.Group
            onClick={toggleAll}
            title={localize(anySelected ? 'DeselectAll' : 'SelectAll')}
            className="cursor-pointer"
            size="large"
          >
            <Icon name="checkmark box" color="grey" />
            <Icon
              name={anySelected ? 'x' : 'checkmark box'}
              className={styles['large-corner-icon']}
              color={anySelected ? 'red' : 'blue'}
              corner
            />
          </Icon.Group>
        </Table.HeaderCell>
        {['Comparisons', 'Fields', 'Operations', 'Values'].map(x => (
          <Table.HeaderCell key={x} content={localize(x)} textAlign="center" />
        ))}
        <Table.HeaderCell textAlign="center">
          <InsertButton onClick={onInsert} title={localize('InsertAtHead')} />
        </Table.HeaderCell>
      </Table.Row>
    </Table.Header>
  )
}

const { bool, func, number } = PropTypes

Header.propTypes = {
  canGroup: bool.isRequired,
  anySelected: bool.isRequired,
  maxShift: number.isRequired,
  group: func.isRequired,
  toggleAll: func.isRequired,
  onInsert: func.isRequired,
  localize: func.isRequired,
}

export default Header
