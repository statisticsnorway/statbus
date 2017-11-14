import React from 'react'
import { arrayOf, func, number, oneOfType, shape, string } from 'prop-types'
import { Item, Confirm, Header } from 'semantic-ui-react'
import { equals } from 'ramda'

import Paginate from 'components/Paginate'
import SearchForm from '../SearchForm'
import ListItem from './ListItem'
import styles from './styles.pcss'

class Search extends React.Component {
  static propTypes = {
    fetchData: func.isRequired,
    updateFilter: func.isRequired,
    setQuery: func.isRequired,
    deleteStatUnit: func.isRequired,
    formData: shape({}).isRequired,
    statUnits: arrayOf(shape({
      regId: number.isRequired,
      name: string.isRequired,
    })),
    query: shape({
      wildcard: string,
      includeLiquidated: string,
    }),
    totalCount: oneOfType([number, string]),
    localize: func.isRequired,
  }

  static defaultProps = {
    query: shape({
      wildcard: '',
      includeLiquidated: false,
    }),
    statUnits: [],
    totalCount: 0,
  }

  state = {
    showConfirm: false,
    selectedUnit: undefined,
  }

  handleChangeForm = (name, value) => {
    this.props.updateFilter({ [name]: value })
  }

  handleSubmitForm = (e) => {
    e.preventDefault()
    const { fetchData, setQuery, query, formData } = this.props
    if (equals(query, formData)) fetchData(query)
    else setQuery({ ...query, ...formData })
  }

  handleConfirm = () => {
    const unit = this.state.selectedUnit
    this.setState({ selectedUnit: undefined, showConfirm: false })
    const { query, formData } = this.props
    const queryParams = { ...query, ...formData }
    this.props.deleteStatUnit(unit.type, unit.regId, queryParams)
  }

  handleCancel = () => {
    this.setState({ showConfirm: false })
  }

  displayConfirm = (statUnit) => {
    this.setState({ selectedUnit: statUnit, showConfirm: true })
  }

  renderRow = item => (
    <ListItem
      key={`${item.regId}_${item.type}_${item.name}`}
      statUnit={item}
      deleteStatUnit={this.displayConfirm}
      localize={this.props.localize}
    />
  )

  renderConfirm() {
    return (
      <Confirm
        open={this.state.showConfirm}
        header={`${this.props.localize('AreYouSure')}?`}
        content={`${this.props.localize('DeleteStatUnitMessage')} "${
          this.state.selectedUnit.name
        }"?`}
        onConfirm={this.handleConfirm}
        onCancel={this.handleCancel}
      />
    )
  }

  render() {
    const { statUnits, formData, localize, totalCount } = this.props
    return (
      <div className={styles.root}>
        <h2>{localize('SearchStatisticalUnits')}</h2>
        {this.state.showConfirm && this.renderConfirm()}
        <br />
        <SearchForm
          formData={formData}
          onChange={this.handleChangeForm}
          onSubmit={this.handleSubmitForm}
          localize={localize}
        />
        <Paginate totalCount={Number(totalCount)}>
          <Item.Group className={styles.items} divided>
            {statUnits.length > 0 ? (
              statUnits.map(this.renderRow)
            ) : (
              <Header as="h2" content={localize('ListIsEmpty')} textAlign="center" disabled />
            )}
          </Item.Group>
        </Paginate>
      </div>
    )
  }
}

export default Search
