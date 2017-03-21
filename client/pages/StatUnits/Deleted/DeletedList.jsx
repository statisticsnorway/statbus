import React from 'react'
import { Item } from 'semantic-ui-react'
import R from 'ramda'

import Paginate from 'components/Paginate'
import SearchForm from './SearchForm'
import ListItem from './ListItem'
import styles from './styles'

const { func, arrayOf, shape, string, number, oneOfType } = React.PropTypes

export default class DeletedList extends React.Component {

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
      wildcard: string,
      includeLiquidated: string,
    }),
    totalPages: oneOfType([number, string]),
    totalCount: oneOfType([number, string]),
  }

  static defaultProps = {
    query: shape({
      wildcard: '',
      includeLiquidated: false,
    }),
    totalPages: 1,
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
    this.props.actions.updateForm({ [name]: value })
  }

  handleSubmitForm = (e) => {
    e.preventDefault()
    const { actions: { setQuery }, query, formData } = this.props
    setQuery({ ...query, ...formData })
  }

  render() {
    const {
      actions: { restore },
      statUnits, formData,
    } = this.props

    const createItem = x => <ListItem key={`${x.regId}_${x.type}`} statUnit={x} restore={restore} />
    const totalCount = Number(this.props.totalCount)
    const totalPages = Number(this.props.totalPages)

    return (
      <div className={styles.root}>
        <SearchForm
          formData={formData}
          onChange={this.handleChangeForm}
          onSubmit={this.handleSubmitForm}
        />
        <Paginate totalPages={totalPages} totalCount={totalCount}>
          <Item.Group divided className={styles.items}>
            {statUnits && statUnits.map(createItem)}
          </Item.Group>
        </Paginate>
      </div>
    )
  }
}
