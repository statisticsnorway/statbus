import React from 'react'
import { Item } from 'semantic-ui-react'
import R from 'ramda'

import Paginate from 'components/Paginate'
import SearchForm from './SearchForm'
import ListItem from './ListItem'
import styles from './styles'

const { func, arrayOf, shape, bool, string, number } = React.PropTypes

class List extends React.Component {

  static propTypes = {
    actions: shape({
      updateForm: func.isRequired,
      setQuery: func.isRequired,
      fetchData: func.isRequired,
      restore: func.isRequired,
    }).isRequired,
    formData: shape({}).isRequired,
    statUnits: arrayOf(shape({
      regId: number.isRequired,
      name: string.isRequired,
    })).isRequired,
    query: shape({
      page: string,
      pageSize: string,
      wildcard: string,
      includeLiquidated: bool,
    }),
    totalPages: number,
  }

  static defaultProps = {
    query: shape({
      page: 1,
      pageSize: 15,
      includeLiquidated: false,
    }),
    totalPages: 1,
  }

  componentDidMount() {
    this.props.actions.fetchData(this.props.query)
  }

  componentWillReceiveProps(nextProps) {
    if (!R.equals(nextProps.query, this.props.query)) {
      nextProps.actions.fetchData(nextProps.query)
    }
  }

  handleChangePagination = (name, value) => {
    const nextQuery = { ...this.props.query, [name]: value }
    this.props.actions.setQuery(nextQuery)
  }

  handleChangeForm = (name, value) => {
    this.props.actions.updateForm({ [name]: value })
  }

  handleSubmitForm = () => {
    const { actions: { setQuery }, query, formData } = this.props
    setQuery({ ...query, ...formData })
  }

  render() {
    const {
      actions: { restore },
      statUnits, totalPages, query, formData,
    } = this.props

    const createItem = x => <ListItem key={x.regId} statUnit={x} restore={restore} />

    return (
      <div className={styles.root}>
        <SearchForm
          formData={{ ...query, ...formData }}
          onChange={this.handleChangeForm}
          onSubmit={this.handleSubmitForm}
        />
        <Paginate {...{ totalPages, onChange: this.handleChangePagination }}>
          <Item.Group divided className={styles.items}>
            {statUnits && statUnits.map(createItem)}
          </Item.Group>
        </Paginate>
      </div>
    )
  }
}

export default List
