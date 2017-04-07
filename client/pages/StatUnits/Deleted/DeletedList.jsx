import React from 'react'
import { Item, Confirm } from 'semantic-ui-react'
import R from 'ramda'

import Paginate from 'components/Paginate'
import { wrapper } from 'helpers/locale'
import SearchForm from '../SearchForm'
import ListItem from './ListItem'
import styles from './styles'

const { func, arrayOf, shape, string, number, oneOfType } = React.PropTypes
class DeletedList extends React.Component {

  static propTypes = {
    actions: shape({
      updateFilter: func.isRequired,
      setQuery: func.isRequired,
      fetchData: func.isRequired,
      restore: func.isRequired,
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
    displayConfirm: false,
    selectedUnit: undefined,
  }

  componentDidMount() {
    this.props.actions.fetchData(this.props.query)
  }

  componentWillReceiveProps(nextProps) {
    if (!R.equals(nextProps.query, this.props.query)) {
      nextProps.actions.fetchData(nextProps.query)
    }
  }

  shouldComponentUpdate(nextProps, nextState) {
    return this.props.localize.lang !== nextProps.localize.lang
      || !R.equals(this.props, nextProps)
      || !R.equals(this.state, nextState)
  }

  handleChangeForm = (name, value) => {
    this.props.actions.updateFilter({ [name]: value })
  }

  handleSubmitForm = (e) => {
    e.preventDefault()
    const { actions: { setQuery }, query, formData } = this.props
    setQuery({ ...query, ...formData })
  }

  showConfirm = (unit) => {
    this.setState({ selectedUnit: unit, displayConfirm: true })
  }

  handleConfirm = () => {
    const unit = this.state.selectedUnit
    const { query, formData } = this.props
    const queryParams = { ...query, ...formData }
    this.setState({ selectedUnit: undefined, displayConfirm: false })
    this.props.actions.restore(unit.type, unit.regId, queryParams)
  }

  handleCancel = () => {
    this.setState({ selectedUnit: undefined, displayConfirm: false })
  }

  renderConfirm = () => (
    <Confirm
      open={this.state.displayConfirm}
      header={`${this.props.localize('AreYouSure')}?`}
      content={`${this.props.localize('UndeleteStatUnitMessage')} "${this.state.selectedUnit.name}"?`}
      onConfirm={this.handleConfirm}
      onCancel={this.handleCancel}
    />
  )

  renderRow = item => (
    <ListItem
      key={`${item.regId}_${item.type}`}
      statUnit={item}
      restore={this.showConfirm}
      localize={this.props.localize}
    />
  )

  render() {
    return (
      <div className={styles.root}>
        {this.state.displayConfirm && this.renderConfirm()}
        <h2>{this.props.localize('SearchDeletedStatisticalUnits')}</h2>
        <SearchForm
          formData={this.props.formData}
          onChange={this.handleChangeForm}
          onSubmit={this.handleSubmitForm}
        />
        <Paginate totalCount={Number(this.props.totalCount)}>
          <Item.Group divided className={styles.items}>
            {this.props.statUnits.map(this.renderRow)}
          </Item.Group>
        </Paginate>
      </div>
    )
  }
}

export default wrapper(DeletedList)
