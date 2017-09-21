import React from 'react'
import { arrayOf, func, number, oneOfType, shape, string } from 'prop-types'
import { Item, Confirm } from 'semantic-ui-react'
import { equals } from 'ramda'

import Paginate from 'components/Paginate'
import SearchForm from '../SearchForm'
import ListItem from './ListItem'
import styles from './styles.pcss'

class Search extends React.Component {
  static propTypes = {
    actions: shape({
      updateFilter: func.isRequired,
      setQuery: func.isRequired,
      fetchData: func.isRequired,
      deleteStatUnit: func.isRequired,
      clear: func.isRequired,
    }).isRequired,
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

  componentDidMount() {
    this.props.actions.fetchData(this.props.query)
    window.scrollTo(0, 0)
  }

  componentWillReceiveProps(nextProps) {
    if (!equals(nextProps.query, this.props.query)) {
      nextProps.actions.fetchData(nextProps.query)
    }
  }

  shouldComponentUpdate(nextProps, nextState) {
    return this.props.localize.lang !== nextProps.localize.lang
      || !equals(this.props, nextProps)
      || !equals(this.state, nextState)
  }

  componentWillUnmount() {
    this.props.actions.clear()
  }

  handleChangeForm = (name, value) => {
    this.props.actions.updateFilter({ [name]: value })
  }

  handleSubmitForm = (e) => {
    e.preventDefault()
    const { actions: { setQuery }, query, formData } = this.props
    setQuery({ ...query, ...formData })
  }

  handleConfirm = () => {
    const unit = this.state.selectedUnit
    this.setState({ selectedUnit: undefined, showConfirm: false })
    const { query, formData } = this.props
    const queryParams = { ...query, ...formData }
    this.props.actions.deleteStatUnit(unit.type, unit.regId, queryParams)
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

  renderConfirm = () => (
    <Confirm
      open={this.state.showConfirm}
      header={`${this.props.localize('AreYouSure')}?`}
      content={`${this.props.localize('DeleteStatUnitMessage')} "${this.state.selectedUnit.name}"?`}
      onConfirm={this.handleConfirm}
      onCancel={this.handleCancel}
    />
  )

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
            {statUnits.map(this.renderRow)}
          </Item.Group>
        </Paginate>
      </div>
    )
  }
}

export default Search
