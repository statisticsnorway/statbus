import React from 'react'
import { Item } from 'semantic-ui-react'
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

  componentDidMount() {
    this.props.actions.fetchData(this.props.query)
  }

  componentWillReceiveProps(nextProps) {
    if (!R.equals(nextProps.query, this.props.query)) {
      nextProps.actions.fetchData(nextProps.query)
    }
  }

  handleChangeForm = (name, value) => {
    this.props.actions.updateFilter({ [name]: value })
  }

  handleSubmitForm = (e) => {
    e.preventDefault()
    const { actions: { setQuery }, query, formData } = this.props
    setQuery({ ...query, ...formData })
  }

  renderRow = item => (
    <ListItem
      key={`${item.regId}_${item.type}`}
      statUnit={item}
      restore={this.props.actions.restore}
      localize={this.props.localize}
    />
  )

  render() {
    return (
      <div className={styles.root}>
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
